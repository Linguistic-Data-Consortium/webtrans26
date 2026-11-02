class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]

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

  def edit
  end

  def update
    if @user.update(params.permit(:name, :password, :password_confirmation))
      # A reset is how you evict someone who knows the old password.
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: "Password and profile have been updated."
    else
      error_message = @user.errors.full_messages.join(", ")
      redirect_to edit_password_path(params[:token]), alert: error_message
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
