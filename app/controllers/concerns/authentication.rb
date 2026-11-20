module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
    # the layout renders it as the s3-available meta tag
    helper_method :cognito_configured?
    # and this one as s3-sessions-available
    helper_method :s3_sessions_configured?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    # A session nobody has used for this long is gone: a browser left open and
    # unattended signs itself out, and a cookie copied off a machine stops
    # working. Someone working is never cut off, since every request is use.
    # Use is recorded at most every SESSION_TOUCH_INTERVAL, to keep a write off
    # every request; that interval is how much earlier than the timeout an idle
    # session can end, so it stays small next to it.
    SESSION_IDLE_TIMEOUT = 2.hours
    SESSION_TOUCH_INTERVAL = 5.minutes

    def find_session_by_cookie
      return unless cookies.signed[:session_id]
      session = Session.find_by(id: cookies.signed[:session_id])
      return unless session
      if session.updated_at < SESSION_IDLE_TIMEOUT.ago
        session.destroy
        return
      end
      session.touch if session.updated_at < SESSION_TOUCH_INTERVAL.ago
      session
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    # Between a right password (or an access link) and the authenticator code:
    # who is signing in, until when, and whether they may then set a password
    # without the old one. Nothing is signed in yet.
    MFA_CHALLENGE_TTL = 5.minutes

    def begin_mfa_challenge(user, password_set_without_current: false)
      session[:mfa_user_id] = user.id
      session[:mfa_expires_at] = MFA_CHALLENGE_TTL.from_now.to_i
      session[:mfa_then_password_without_current] = password_set_without_current
    end

    def mfa_challenge_user
      return if session[:mfa_user_id].blank? || session[:mfa_expires_at].to_i < Time.now.to_i
      User.find_by(id: session[:mfa_user_id])
    end

    def end_mfa_challenge
      session.delete(:mfa_user_id)
      session.delete(:mfa_expires_at)
      session.delete(:mfa_then_password_without_current)
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
      reset_session # return_to and flash shouldn't outlive the sign-in
    end

    def cognito_init
      @pool_id ||= Rails.application.credentials.cognito_pool_id
      @provider_name ||= Rails.application.credentials.cognito_provider_name
    end

    # Whether this instance can vend S3 credentials at all.
    #
    # The browser reaches S3 only through POST /token — aws_helper.js builds its
    # client from fromCognitoIdentity and has no other route — so without these
    # three things every s3:// source and the whole bucket browser are dead. The
    # region matters as much as the credentials: Aws::CognitoIdentity::Client.new
    # raises MissingRegionError before the pool id is ever used.
    #
    # Checked rather than assumed, because the failure was silent. /token used to
    # return a 500, the client's .catch logged it and resolved to undefined, and
    # every caller then hit "cannot read properties of undefined" with nothing
    # pointing at the cause.
    def cognito_configured?
      cognito_init
      @pool_id.present? &&
        @provider_name.present? &&
        (ENV["AWS_REGION"].present? || Aws.config[:region].present?)
    end

    # Whether this instance can vend per-project S3 sessions — POST
    # /s3_session, aws/s3_project_prefixes.md. Separate from
    # cognito_configured? on purpose: the two mechanisms are gated
    # independently, and with neither set the app behaves as it always has.
    #
    # The region is checked for the same reason as above: Aws::STS::Client.new
    # raises MissingRegionError before the role is ever named.
    def s3_sessions_configured?
      x = Rails.application.config.x
      x.s3_bucket.present? &&
        x.s3_role_arn.present? &&
        (ENV["AWS_REGION"].present? || Aws.config[:region].present?)
    end

    # get a cognito token linked to the currently logged in user
    def get_credentials_from_cognito(user_id)
      cognito_init
      puts "\nnew token\n"
      params = {
        identity_pool_id: @pool_id,
        logins: { @provider_name => user_id.to_s },
        token_duration: 15 * 60 # 15 min validitiy; it's the default, but be explicit
      }
      cog = Aws::CognitoIdentity::Client.new
      tmp = cog.get_open_id_token_for_developer_identity(params).data.to_h
      tok = {
        identityId: tmp[:identity_id],
        logins: { 'cognito-identity.amazonaws.com': tmp[:token] }
      }
      region = ENV["AWS_REGION"]
      { tok:, region: }
    end

end
