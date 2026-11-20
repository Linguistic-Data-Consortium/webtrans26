# The second step of signing in when MFA is on: a code from the user's
# authenticator app, or one of their recovery codes (User::Mfa). Reached only
# after a right password (SessionsController) or an access link
# (AccessLinksController), which leave a short-lived challenge in the session.
#
# Wrong codes count toward the sign-in lockout like wrong passwords, so a
# stolen password isn't a free run at guessing codes.
class SessionMfasController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_unexpired_password
  skip_before_action :require_mfa_enrollment
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_url, alert: "Try again later." }

  before_action :set_challenge_user

  def new
  end

  def create
    if @user.locked?
      end_mfa_challenge
      redirect_to new_session_path, alert: SessionsController::FAILED
    elsif @user.verify_second_factor(params[:code])
      without_current = session[:mfa_then_password_without_current]
      end_mfa_challenge
      @user.clear_sign_in_failures
      start_new_session_for @user
      if without_current
        session[:password_set_without_current] = true
        redirect_to edit_account_password_path, notice: "Welcome, #{@user.name}. Choose a password to finish signing in."
      else
        redirect_to after_authentication_url
      end
    else
      @user.register_failed_sign_in
      if @user.reload.locked?
        end_mfa_challenge
        redirect_to new_session_path, alert: SessionsController::FAILED
      else
        redirect_to new_session_mfa_path, alert: "That code didn't work. Try the current one from your app, or a recovery code."
      end
    end
  end

  private

  def set_challenge_user
    @user = mfa_challenge_user
    return if @user
    end_mfa_challenge
    redirect_to new_session_path, alert: "Please sign in again."
  end
end
