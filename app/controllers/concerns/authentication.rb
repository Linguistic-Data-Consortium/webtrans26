module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
    # the layout renders it as the s3-available meta tag
    helper_method :cognito_configured?
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

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
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
