require "test_helper"

# Accounts unused for INACTIVE_ACCOUNT_DAYS (180 by default) are disabled.
class InactiveAccountTest < ActiveSupport::TestCase
  setup { @alice = users(:alice) }

  test "an account used within the limit is left alone" do
    @alice.update_columns(last_active_at: 179.days.ago)
    assert_not @alice.inactive_too_long?
    assert_equal 0, User.disable_inactive!
    assert @alice.reload.activated?
  end

  test "an account unused for longer is disabled, and signed out everywhere" do
    @alice.update_columns(last_active_at: 181.days.ago)
    @alice.sessions.create!(user_agent: "t", ip_address: "127.0.0.1")
    assert_equal 1, DisableInactiveAccountsJob.perform_now
    @alice.reload
    assert_not @alice.activated?
    assert @alice.disabled_for_inactivity?
    assert_empty @alice.sessions
  end

  test "with no recorded use, the account's creation is what counts" do
    @alice.update_columns(last_active_at: nil, created_at: 200.days.ago)
    assert @alice.inactive_too_long?
  end

  test "accounts never activated aren't 'disabled' — they're already inactive" do
    users(:unactivated).update_columns(last_active_at: 300.days.ago)
    assert_not_includes User.inactive_too_long, users(:unactivated)
  end

  test "re-enabling starts the clock again" do
    @alice.update_columns(last_active_at: 181.days.ago)
    @alice.disable_for_inactivity!
    @alice.activate
    assert @alice.activated?
    assert_nil @alice.disabled_at
    assert_not @alice.inactive_too_long?
  end

  test "use is recorded at most daily" do
    @alice.update_columns(last_active_at: 2.days.ago)
    @alice.record_activity
    assert_in_delta Time.current, @alice.reload.last_active_at, 5
    stamp = @alice.last_active_at
    @alice.record_activity
    assert_equal stamp, @alice.reload.last_active_at
  end

  test "INACTIVE_ACCOUNT_DAYS sets the limit" do
    Rails.application.config.x.inactive_account_days = 30
    @alice.update_columns(last_active_at: 31.days.ago)
    assert @alice.inactive_too_long?
  ensure
    Rails.application.config.x.inactive_account_days = 180
  end
end
