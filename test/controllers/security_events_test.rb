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

  # ── memberships, accounts, sessions, configuration ─────────────────────

  test "adding and removing project and task members is recorded, with who did it" do
    charlie = users(:charlie)
    sign_in_as @alice # owner of alpha, admin of alpha_task_one
    post project_users_url, params: { project_id: projects(:alpha).id, user_id: charlie.id }, as: :json
    e = last("project_member.added")
    assert_equal [ charlie.id, @alice.id, projects(:alpha).name ], [ e.user_id, e.actor_id, e.details["project"] ]

    post task_users_url, params: { task_id: tasks(:alpha_task_one).id, user_id: charlie.id }, as: :json
    assert_equal charlie.id, last("task_member.added").user_id

    tu = TaskUser.find_by!(task: tasks(:alpha_task_one), user: charlie)
    delete task_user_url(tu), as: :json
    assert_equal [ charlie.id, @alice.id ], [ last("task_member.removed").user_id, last("task_member.removed").actor_id ]

    pu = ProjectUser.find_by!(project: projects(:alpha), user: charlie)
    delete project_user_url(pu), as: :json
    assert_equal charlie.id, last("project_member.removed").user_id
  end

  test "a role flag on a membership is recorded once, from the model" do
    sign_in_as @alice
    pu = project_users(:bob_on_alpha)
    assert_difference -> { SecurityEvent.where(event: "project_role.changed").count }, 1 do
      patch project_user_url(pu), params: { admin: true }, as: :json
    end
    assert_equal true, last("project_role.changed").details["admin"]
  end

  test "deactivating by hand is recorded with who did it, and a portal manager can't deactivate an admin" do
    sign_in_as users(:pat) # portal manager
    patch deactivate_user_url(@alice), as: :json
    assert_not @alice.reload.activated?
    assert_equal [ @alice.id, users(:pat).id ], [ last("account.deactivated").user_id, last("account.deactivated").actor_id ]

    patch deactivate_user_url(@admin), as: :json
    assert_response :forbidden
    assert @admin.reload.activated?
  end

  test "granting and revoking system admin is recorded, from the console as well" do
    @alice.update!(admin: true)
    assert_equal @alice.id, last("admin.granted").user_id
    @alice.update_attribute(:admin, false)
    assert_equal @alice.id, last("admin.revoked").user_id
  end

  test "a session that timed out is recorded when it's next used, and by the sweep" do
    sign_in_as @alice
    @alice.sessions.update_all(updated_at: 31.minutes.ago)
    get user_path(@alice)
    assert_equal "next_use", last("session.expired").details["via"]

    stale = users(:bob).sessions.create!(user_agent: "t", ip_address: "127.0.0.1")
    stale.update_columns(updated_at: 2.hours.ago)
    assert_equal 1, ExpireIdleSessionsJob.perform_now
    e = last("session.expired")
    assert_equal [ users(:bob).id, "sweep" ], [ e.user_id, e.details["via"] ]
    assert_not Session.exists?(stale.id)
  end

  test "a sign-out by the screen lock says so" do
    sign_in_as @alice
    delete session_url(idle: 1)
    assert_equal "screen_lock", last("sign_out").details["reason"]
  end

  test "changes to kit types, features and workflows are recorded, naming the fields" do
    kit_types(:advanced).update_columns(node_class_id: NodeClass.create!(name: "AuditCheck:Root").id)
    sign_in_as @admin
    patch kit_type_url(kit_types(:advanced)), params: { kit_type: { name: "renamed_type" } }, as: :json
    e = last("kit_type.changed")
    assert_equal [ "updated", [ "name" ], @admin.id ], [ e.details["action"], e.details["fields"], e.actor_id ]

    Feature.create!(name: "f1", value: "f1", category: "task")
    assert_equal "created", last("feature.changed").details["action"]

    WorkflowSameListForEveryone.create!(name: "AuditedList")
    assert_equal "created", last("workflow.changed").details["action"]
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
