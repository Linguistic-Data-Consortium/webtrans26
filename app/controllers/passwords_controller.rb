class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit ]
  before_action :set_user_from_session, only: %i[ reset_form reset ]

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

  # The emailed link, /passwords/:token/edit. The token is moved into the
  # session and the browser sent on to a URL without it, so the form, its
  # submission and any redirect after it never put a live reset token in a path,
  # where request logs would record it. The invite flow hands one over the same
  # way (InvitesController#edit).
  def edit
    session[:password_reset_token] = params[:token]
    redirect_to reset_password_path
  end

  def reset_form
    render :edit
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
