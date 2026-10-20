# Lets a signed-in user change their own password (the dashboard's Account
# tab). Distinct from PasswordsController, which is the signed-out reset flow
# and allows unauthenticated access — here authentication is required, and the
# current password has to be supplied.
class AccountPasswordsController < ApplicationController
  MINIMUM_LENGTH = 8

  # Changing a password needs the old one, so throttle it the way sign-in is
  # throttled rather than leaving it as an unlimited guessing oracle.
  rate_limit to: 10, within: 3.minutes, only: :update,
             with: -> { render json: { error: "Too many attempts. Try again in a few minutes." }, status: 429 }

  def update
    respondj do
      current = params[:current_password].to_s
      password = params[:password].to_s
      confirmation = params[:password_confirmation].to_s

      if !current_user.authenticate(current)
        { error: "Your current password is not correct." }
      elsif password.length < MINIMUM_LENGTH
        { error: "The new password must be at least #{MINIMUM_LENGTH} characters." }
      elsif password != confirmation
        { error: "The new password and its confirmation don't match." }
      elsif current_user.update(password: password, password_confirmation: confirmation)
        { ok: "Your password has been changed.#{sign_out_other_sessions}" }
      else
        { errors: current_user.errors.full_messages }
      end
    end
  end

  private

  # Everything except the browser making this request — a password change is
  # how you evict a device you no longer control (or an old access link).
  def sign_out_other_sessions
    others = current_user.sessions.where.not(id: Current.session&.id)
    count = others.count
    others.destroy_all
    count.zero? ? "" : " Signed out #{count} other session#{count == 1 ? '' : 's'}."
  end
end
