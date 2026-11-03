class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit ]
  before_action :set_user_from_session, only: %i[ reset ]

  MAILLESS_NOTICE = "This instance doesn't send email, so passwords can't be reset here. " \
    "Ask a portal manager or administrator for a sign-in link, then change your password on the Account tab."

  def new
  end

  def create
    # Mail is opt-in (see config.x.mail_enabled). Without it there is no way to
    # prove the requester owns the address, so this changes nothing: recovery is
    # an access link from an administrator, then the Account tab. (It used to set
    # the submitted password and deactivate the account, which let anyone who knew
    # an address lock that user out, or choose the password an admin would later
    # reactivate.)
    return redirect_to(new_session_path, notice: MAILLESS_NOTICE) if !Rails.application.config.x.mail_enabled

    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_now
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  # A reset token must never be in a URL path, where the app's log and any
  # proxy's log would record it while it is still live. The emailed link is
  # /passwords/reset#<token>: a browser never sends the fragment, so the first
  # request carries no token, and the claim page's script posts it (see
  # #claim). From there the token lives in the session. The invite flow hands
  # one over the same way (InvitesController#edit).
  #
  # /passwords/:token/edit is the older form of the link. It is kept so that a
  # link already sent still works, and it moves its token into the session at
  # once. Those links are dead within 15 minutes of being sent.
  def edit
    session[:password_reset_token] = params[:token]
    redirect_to reset_password_path
  end

  # The form when the session holds a token, the claim page when it doesn't.
  def reset_form
    return render(:claim) if session[:password_reset_token].blank?
    set_user_from_session
    render :edit unless performed?
  end

  # The claim page's script posts the fragment's token here, in the body.
  def claim
    session[:password_reset_token] = params[:token].to_s
    redirect_to reset_password_path
  end

  def reset
    if @user.update(params.permit(:name, :password, :password_confirmation))
      session.delete(:password_reset_token)
      # A reset is how you evict someone who knows the old password.
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: "Password and profile have been updated."
    else
      error_message = @user.errors.full_messages.join(", ")
      redirect_to reset_password_path, alert: error_message
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end

    def set_user_from_session
      @user = User.find_by_password_reset_token!(session[:password_reset_token].to_s)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      session.delete(:password_reset_token)
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
