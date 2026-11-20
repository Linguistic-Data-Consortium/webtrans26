class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  skip_before_action :require_unexpired_password
  skip_before_action :require_mfa_enrollment
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_url, alert: "Try again later." }

  # ?idle=1 is where the screen lock (idle_lock.js) sends a page it cleared.
  def new
    flash.now[:notice] = "You were signed out after #{Authentication.session_idle_timeout.in_minutes.round} minutes without activity." if params[:idle]
  end

  # One answer for every failure: a wrong password, an unknown address, and a
  # locked account (even with the right password). Telling them apart would say
  # which addresses have accounts, and which are locked.
  FAILED = "Try another email address or password. After #{User::LOCKOUT_ATTEMPTS} failed attempts " \
    "in a row, an account is locked for #{User::LOCKOUT_PERIOD.in_minutes.to_i} minutes."

  # Shown only after a right password, like "not activated": it says nothing
  # to someone guessing.
  DISABLED = "This account was disabled after #{User.inactive_after.in_days.to_i} days without use. " \
    "Ask an administrator to re-enable it."

  def create
    # authenticate_by takes the same time whether or not the address exists.
    user = User.authenticate_by(params.permit(:email_address, :password))
    account = user || User.find_by(email_address: params[:email_address].to_s)

    # The address as typed goes in the log for a failure with no account
    # behind it; never the password.
    email = params[:email_address].to_s.strip.downcase.truncate(255)
    if account&.locked?
      audit("sign_in.locked_out", user: account)
      redirect_to new_session_path, alert: FAILED
    elsif user.nil?
      record_failed_sign_in(account, email: (email unless account))
      redirect_to new_session_path, alert: FAILED
    elsif user.inactive_too_long? || user.disabled_for_inactivity?
      user.disable_for_inactivity! unless user.disabled_for_inactivity?
      user.clear_sign_in_failures
      audit("sign_in.disabled", user: user)
      redirect_to new_session_path, alert: DISABLED
    elsif user.activated? && user.mfa_challenge?
      # The password was right; the code from their authenticator comes next.
      # The failure count isn't cleared until that's right too, or a stolen
      # password could reset it between guesses at the code.
      begin_mfa_challenge(user)
      redirect_to new_session_mfa_path
    elsif user.activated?
      user.clear_sign_in_failures
      start_new_session_for user
      audit("sign_in.success", user: user)
      redirect_to after_authentication_url
    else
      user.clear_sign_in_failures
      audit("sign_in.not_activated", user: user)
      redirect_to new_session_path, alert: "Your account hasn't been activated yet."
    end
  end

  def destroy
    # ?idle=1 when the screen lock signed out (idle_lock.js).
    audit("sign_out", user: Current.session&.user, reason: (params[:idle] ? "screen_lock" : nil))
    terminate_session
    redirect_to new_session_path
  end
end
