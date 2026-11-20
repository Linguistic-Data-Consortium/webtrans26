require "test_helper"

# The security audit log (SecurityEvent): what's recorded, that it can't be
# changed, and who can read it.
class SecurityEventsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    @admin = users(:admin)
  end

  def last(event)
    SecurityEvent.where(event: event).order(:id).last
  end

  # ── what's recorded ────────────────────────────────────────────────────

  test "a sign-in is recorded with the address it came from" do
    sign_in_as @alice
    e = last("sign_in.success")
    assert_equal @alice.id, e.user_id
    assert_equal "127.0.0.1", e.ip
  end

  test "a wrong password is recorded against the account, and never the password" do
    post session_url, params: { email_address: @alice.email_address, password: "Wr0ng-and-secret!" }
    e = last("sign_in.failure")
    assert_equal @alice.id, e.user_id
    assert_not_includes SecurityEvent.all.map { |r| r.details.to_json }.join, "Wr0ng-and-secret!"
  end

  test "an unknown address is recorded as typed, with no user" do
    post session_url, params: { email_address: "Nobody@Example.com", password: "x" }
    e = last("sign_in.failure")
    assert_nil e.user_id
    assert_equal({ "email" => "nobody@example.com" }, e.details)
  end

  test "the failure that locks an account is followed by the lock, and later tries by locked_out" do
    3.times { post session_url, params: { email_address: @alice.email_address, password: "wrong" } }
    assert last("account.locked")
    sign_in_as @alice
    assert_equal @alice.id, last("sign_in.locked_out").user_id
  end

  test "signing out and changing a password are recorded" do
    sign_in_as @alice
    patch account_password_url, params: { current_password: "password123",
      password: GOOD_PASSWORD, password_confirmation: GOOD_PASSWORD }, as: :json
    assert_equal @alice.id, last("password.changed").user_id
    delete session_url
    assert_equal @alice.id, last("sign_out").user_id
  end

  test "an administrator's actions record who did them" do
    sign_in_as @admin
    post group_users_url, params: { group_id: groups(:project_managers).id, user_id: @alice.id }, as: :json
    e = last("group.added")
    assert_equal [ @alice.id, @admin.id, "Project Managers" ], [ e.user_id, e.actor_id, e.details["group"] ]

    post access_links_url, params: { email_address: @alice.email_address, name: @alice.name }, as: :json
    assert_equal @admin.id, last("access_link.created").actor_id
  end

  test "two-step sign-in events are recorded" do
    secret, codes = enroll_mfa(@alice)
    with_mfa_enabled do
      sign_in_as @alice
      post session_mfa_path, params: { code: "000000" }
      assert_equal @alice.id, last("mfa.failure").user_id
      post session_mfa_path, params: { code: codes.first }
      assert_equal 9, last("mfa.recovery_code_used").details["recovery_codes_left"]
    end
  end

  test "disabling an account for inactivity is recorded, with no actor" do
    @alice.update_columns(last_active_at: 181.days.ago)
    DisableInactiveAccountsJob.perform_now
    e = last("account.disabled_inactive")
    assert_equal @alice.id, e.user_id
    assert_nil e.actor_id
  end

  # ── append-only ────────────────────────────────────────────────────────

  test "a recorded event can't be changed or deleted" do
    e = SecurityEvent.record("sign_out", user: @alice)
    assert_raises(ActiveRecord::ReadOnlyRecord) { e.update!(event: "sign_in.success") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { e.destroy }
    assert SecurityEvent.exists?(e.id)
  end

  test "recording never breaks the request it describes" do
    assert_nil SecurityEvent.record("not.an.event", user: @alice)
  end

  # ── reading it ─────────────────────────────────────────────────────────

  test "only a system admin can read the log" do
    sign_in_as users(:pat) # portal manager, not admin
    get security_events_path
    assert_redirected_to root_path
  end

  test "an admin sees events, filtered by event and by user" do
    post session_url, params: { email_address: @alice.email_address, password: "wrong" }
    post session_url, params: { email_address: users(:bob).email_address, password: "wrong" }
    sign_in_as @admin
    get security_events_path, params: { event: "sign_in.failure", user: @alice.email_address }
    assert_response :success
    assert_select "#security-events tbody tr", 1
    assert_match @alice.email_address, css_select("#security-events tbody").text
  end

  test "the log downloads as CSV" do
    post session_url, params: { email_address: @alice.email_address, password: "wrong" }
    sign_in_as @admin
    get security_events_path(format: :csv, event: "sign_in.failure")
    assert_equal "text/csv", response.media_type
    rows = CSV.parse(response.body, headers: true)
    assert_equal [ "sign_in.failure" ], rows.map { |r| r["event"] }.uniq
    assert_equal @alice.email_address, rows.first["user_email"]
  end
end
