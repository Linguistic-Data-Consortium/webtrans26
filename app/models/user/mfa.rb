# Two-step sign-in with an authenticator app (TOTP: the six-digit codes that
# Google Authenticator, 1Password, Duo Mobile and the rest show), switched on for
# every user by MFA_ENABLED and off by default.
#
# With it on, a user who hasn't set it up is sent to /account/mfa at their next
# request (ApplicationController#require_mfa_enrollment), and one who has is
# asked for a code after their password (SessionMfaController). Each user gets
# RECOVERY_CODE_COUNT single-use recovery codes for a lost phone. An admin
# clears it with `bin/rails mfa:reset EMAIL=...`, which makes the user set it
# up again.
#
# The shared secret is stored encrypted under a key derived from
# secret_key_base. Codes are accepted from DRIFT seconds either side of now,
# and never twice: otp_last_step remembers the newest one used.
module User::Mfa
  extend ActiveSupport::Concern

  RECOVERY_CODE_COUNT = 10
  DRIFT = 30
  INTERVAL = 30

  class_methods do
    def mfa_enabled? = Rails.application.config.x.mfa_enabled

    def new_otp_secret = ROTP::Base32.random

    def otp_encryptor
      key = Rails.application.key_generator.generate_key("user otp secret", ActiveSupport::MessageEncryptor.key_len)
      ActiveSupport::MessageEncryptor.new(key)
    end
  end

  def mfa_enrolled?
    otp_enabled_at.present? && otp_secret_ciphertext.present?
  end

  # On for this instance and set up by this user: sign-in asks for a code.
  def mfa_challenge?
    User.mfa_enabled? && mfa_enrolled?
  end

  # On for this instance but not yet set up by this user.
  def mfa_setup_required?
    User.mfa_enabled? && !mfa_enrolled?
  end

  # What an authenticator app scans: the secret, labelled with the issuer and
  # this account's address.
  def otp_provisioning_uri(secret)
    ROTP::TOTP.new(secret, issuer: Rails.application.config.x.mfa_issuer).provisioning_uri(email_address)
  end

  # Finish setting up: +code+ must come from +secret+, which proves the app
  # has it. Returns the recovery codes, in the clear for showing once, or nil
  # if the code was wrong.
  def enroll_mfa(secret, code)
    step = totp_step(secret, code, after_step: nil) or return nil
    codes = new_recovery_codes
    update!(otp_secret_ciphertext: User.otp_encryptor.encrypt_and_sign(secret),
            otp_enabled_at: Time.current, otp_last_step: step,
            otp_recovery_digests: codes.map { |c| User.digest(normalize_recovery(c)) })
    codes
  end

  # The second step of sign-in: a current code from the app, or an unused
  # recovery code (which is used up). True if it was either.
  def verify_second_factor(code)
    code = code.to_s.strip
    return false unless mfa_enrolled? && code.present?
    if code.delete(" ").match?(/\A\d{6}\z/)
      step = totp_step(otp_secret, code, after_step: otp_last_step) or return false
      # Claim the step in one UPDATE, so the same code can't be used twice at
      # once either.
      User.where(id: id).where("otp_last_step IS NULL OR otp_last_step < ?", step)
          .update_all(otp_last_step: step) == 1
    else
      use_recovery_code(code)
    end
  end

  def recovery_codes_left
    Array(otp_recovery_digests).size
  end

  # A fresh set, replacing the old. Returns them in the clear, to show once.
  def regenerate_recovery_codes
    codes = new_recovery_codes
    update_columns(otp_recovery_digests: codes.map { |c| User.digest(normalize_recovery(c)) })
    codes
  end

  # Forget the authenticator. With MFA on, the user sets it up again at their
  # next request.
  def reset_mfa!
    update_columns(otp_secret_ciphertext: nil, otp_enabled_at: nil, otp_last_step: nil, otp_recovery_digests: nil)
  end

  private

  def otp_secret
    otp_secret_ciphertext && User.otp_encryptor.decrypt_and_verify(otp_secret_ciphertext)
  end

  # The 30-second step +code+ belongs to, if it's valid now and newer than
  # +after_step+.
  def totp_step(secret, code, after_step:)
    at = ROTP::TOTP.new(secret).verify(code.to_s.delete(" "), drift_behind: DRIFT, drift_ahead: DRIFT,
                                       after: after_step && (after_step * INTERVAL))
    at && at / INTERVAL
  end

  # xxxxx-xxxxx, lowercase letters and digits.
  def new_recovery_codes
    Array.new(RECOVERY_CODE_COUNT) { SecureRandom.alphanumeric(10).downcase.scan(/.{5}/).join("-") }
  end

  def normalize_recovery(code)
    code.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  def use_recovery_code(code)
    given = normalize_recovery(code)
    return false if given.length != 10
    with_lock do
      match = Array(otp_recovery_digests).find { |d| BCrypt::Password.new(d).is_password?(given) }
      return false unless match
      update_columns(otp_recovery_digests: otp_recovery_digests - [ match ])
    end
    true
  end
end
