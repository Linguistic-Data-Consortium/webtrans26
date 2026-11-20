# Two-step sign-in with an authenticator app (User::Mfa). Used only when
# MFA_ENABLED is set.
#
#   otp_secret_ciphertext  the shared TOTP secret, encrypted (never stored plain)
#   otp_enabled_at         when the user confirmed their authenticator
#   otp_last_step          the 30-second step of the last code accepted, so a
#                          code can't be used twice
#   otp_recovery_digests   bcrypt digests of the unused one-time recovery codes
class AddMfaToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :otp_secret_ciphertext, :text
    add_column :users, :otp_enabled_at, :datetime
    add_column :users, :otp_last_step, :bigint
    add_column :users, :otp_recovery_digests, :json
  end
end
