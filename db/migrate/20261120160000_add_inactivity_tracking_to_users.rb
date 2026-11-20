# Accounts unused for INACTIVE_ACCOUNT_DAYS are disabled (User#inactive_too_long?).
#
#   last_active_at  the last sign-in or use, recorded at most daily
#   disabled_at     when the account was disabled for that, so the sign-in page
#                   and the admin's list can say why it's inactive
#
# Existing accounts get the most recent use there's evidence of: a session,
# an annotation they wrote, their activation, their creation. Accounts already
# past the limit on that evidence are disabled by the first run of
# DisableInactiveAccountsJob, or at their next sign-in.
class AddInactivityTrackingToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :last_active_at, :datetime
    add_column :users, :disabled_at, :datetime

    select_rows("SELECT id, activated_at, created_at FROM users").each do |id, activated_at, created_at|
      seen = [
        select_value("SELECT MAX(updated_at) FROM sessions WHERE user_id = #{Integer(id)}"),
        select_value("SELECT MAX(created_at) FROM annotations WHERE user_id = #{Integer(id)}"),
        activated_at, created_at
      ].compact.map { |t| t.is_a?(String) ? Time.zone.parse(t) : t }.max
      update("UPDATE users SET last_active_at = #{quote(seen)} WHERE id = #{Integer(id)}") if seen
    end
  end

  def down
    remove_column :users, :disabled_at
    remove_column :users, :last_active_at
  end
end
