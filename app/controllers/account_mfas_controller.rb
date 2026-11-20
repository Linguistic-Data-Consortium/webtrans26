# Setting up two-step sign-in (User::Mfa), and seeing or replacing the recovery
# codes once it is. Where ApplicationController#require_mfa_enrollment sends a
# signed-in user who hasn't set it up, when MFA_ENABLED.
#
# The secret being set up lives in the session (encrypted, as the session
# cookie is) until a code from the app proves the app has it. Only then is it
# saved, so a half-finished setup leaves nothing behind.
class AccountMfasController < ApplicationController
  skip_before_action :require_mfa_enrollment
  rate_limit to: 10, within: 3.minutes, only: %i[ create recovery_codes ],
             with: -> { redirect_to account_mfa_path, alert: "Too many attempts. Try again in a few minutes." }

  def show
    return render(:disabled) unless User.mfa_enabled?
    return if current_user.mfa_enrolled?

    session[:mfa_setup_secret] ||= User.new_otp_secret
    @secret = session[:mfa_setup_secret]
    @qr_svg = RQRCode::QRCode.new(current_user.otp_provisioning_uri(@secret))
                             .as_svg(module_size: 4, standalone: true, use_path: true, viewbox: true)
    render :setup
  end

  # Confirm setup with a code from the app.
  def create
    secret = session[:mfa_setup_secret]
    if current_user.mfa_enrolled? || secret.blank?
      redirect_to account_mfa_path
    elsif (@codes = current_user.enroll_mfa(secret, params[:code]))
      session.delete(:mfa_setup_secret)
      flash.now[:notice] = "Two-step sign-in is set up."
      render :recovery_codes
    else
      redirect_to account_mfa_path, alert: "That code didn't match. Check the app shows this account, and try the current code."
    end
  end

  # A fresh set of recovery codes, for a current code from the app (not a
  # recovery code: that would let the codes renew themselves).
  def recovery_codes
    code = params[:code].to_s.delete(" ")
    if current_user.mfa_enrolled? && code.match?(/\A\d{6}\z/) && current_user.verify_second_factor(code)
      @codes = current_user.regenerate_recovery_codes
      flash.now[:notice] = "New recovery codes. The old ones no longer work."
      render :recovery_codes
    else
      redirect_to account_mfa_path, alert: "That code didn't work. Use the current code from your authenticator app."
    end
  end
end
