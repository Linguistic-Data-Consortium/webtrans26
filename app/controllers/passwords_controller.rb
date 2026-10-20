class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]

  def new
  end

  def create
    # Mail is opt-in (see config.x.mail_enabled). When it's off the user
    # submits a new password directly on the form; we set it and deactivate
    # the account in one go. An administrator has to verify and reactivate
    # before the user can sign in again.
    return create_mailless if !Rails.application.config.x.mail_enabled

    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_now
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  def edit
  end

  def update
    if @user.update(params.permit(:name, :password, :password_confirmation))
      redirect_to new_session_path, notice: "Password and profile have been updated."
    else
      error_message = @user.errors.full_messages.join(", ")
      redirect_to edit_password_path(params[:token]), alert: error_message
    end
  end

  private
    # Sets the chosen password on the matching account (if any) and parks
    # the account by deactivating it. Validation runs before the user
    # lookup so the response shape doesn't change based on whether the
    # email matched — that would otherwise leak account existence.
    def create_mailless
      new_password = params[:password].to_s

      if new_password.length < 8
        flash[:alert] = "Password must be at least 8 characters."
        return redirect_to new_password_path
      end
      if new_password != params[:password_confirmation].to_s
        flash[:alert] = "Password confirmation doesn't match."
        return redirect_to new_password_path
      end

      if user = User.find_by(email_address: params[:email_address])
        user.update(password: new_password, password_confirmation: new_password)
        user.deactivate
      end

      redirect_to new_session_path,
        notice: "If the address matched an account, your new password has been set and the account has been deactivated. Please ask an administrator to verify and reactivate you."
    end

    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
