# Lets a signed-in user change their own password: from the dashboard's Account
# tab (JSON), or on the page anyone is sent to when their password has expired
# or was never chosen (#edit, HTML). Distinct from PasswordsController, which is
# the signed-out reset flow. What makes a password acceptable is
# PasswordPolicy, checked by User.
#
# The current password is required, except straight after signing in with an
# access link: that link is how someone gets in without knowing it, so the
# session it starts may set a new one without it, once.
class AccountPasswordsController < ApplicationController
  skip_before_action :require_unexpired_password

  # Changing a password needs the old one, so throttle it the way sign-in is
  # throttled rather than leaving it as an unlimited guessing oracle.
  rate_limit to: 10, within: 3.minutes, only: :update,
             with: -> { render json: { error: "Too many attempts. Try again in a few minutes." }, status: 429 }

  def edit
    @needs_current = !session[:password_set_without_current]
    @expired = current_user.password_expired?
  end

  def update
    result = change_password
    respond_to do |format|
      format.json { render json: result }
      format.html do
        if result[:ok]
          redirect_to root_path, notice: result[:ok]
        else
          redirect_to edit_account_password_path, alert: result[:error] || result[:errors].join(". ")
        end
      end
    end
  end

  private

  def change_password
    current = params[:current_password].to_s
    password = params[:password].to_s
    confirmation = params[:password_confirmation].to_s

    if !session[:password_set_without_current] && !current_user.authenticate(current)
      { error: "Your current password is not correct." }
    elsif password != confirmation
      { error: "The new password and its confirmation don't match." }
    elsif current_user.update(password: password, password_confirmation: confirmation)
      session.delete(:password_set_without_current)
      { ok: "Your password has been changed.#{sign_out_other_sessions}" }
    else
      { errors: current_user.errors.full_messages }
    end
  end

  # Everything except the browser making this request — a password change is
  # how you evict a device you no longer control (or an old access link).
  def sign_out_other_sessions
    others = current_user.sessions.where.not(id: Current.session&.id)
    count = others.count
    others.destroy_all
    count.zero? ? "" : " Signed out #{count} other session#{count == 1 ? '' : 's'}."
  end
end
