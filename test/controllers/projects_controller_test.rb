require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)         # owner+admin of alpha
    @bob = users(:bob)             # member of alpha, not on beta
    @admin = users(:admin)         # system admin
    @pat = users(:pat)             # portal manager, no project membership
    @alpha = projects(:alpha)
    @beta = projects(:beta)
  end

  # ── index ─────────────────────────────────────────────────────────────────

  test "index returns only the current user's projects for a non-lead annotator" do
    sign_in_as @bob
    get projects_url, as: :json
    assert_response :success
    names = JSON.parse(@response.body).map { |p| p["name"] }
    assert_equal [@alpha.name], names
  end

  test "index returns all projects for an admin" do
    sign_in_as @admin
    get projects_url, as: :json
    assert_response :success
    names = JSON.parse(@response.body).map { |p| p["name"] }
    assert_includes names, @alpha.name
    assert_includes names, @beta.name
  end

  test "index requires authentication" do
    get projects_url, as: :json
    assert_redirected_to new_session_path
  end

  # ── show ──────────────────────────────────────────────────────────────────

  test "show returns full project details for a member" do
    sign_in_as @bob
    get project_url(@alpha), as: :json
    body = JSON.parse(@response.body)
    assert_equal @alpha.id, body["id"]
    assert_equal @alpha.name, body["name"]
    assert body.key?("members")
    assert body.key?("tasks")
  end

  # The Project Tasks table's "Available Kits" column. For most workflows it's
  # the unassigned kits; for one that makes a user's kits when they arrive,
  # those kits don't exist yet and counting them would say there's nothing to
  # do on a task nobody has started.
  test "show counts unassigned kits as available work" do
    task = tasks(:alpha_task_one)
    2.times do |i|
      Kit.create!(task_id: task.id, kit_type_id: task.kit_type_id, state: "unassigned",
                  uid: "avail-#{i}-#{SecureRandom.hex(3)}", tree_id: 1)
    end
    sign_in_as @alice

    get project_url(@alpha), as: :json
    row = JSON.parse(@response.body)["tasks"].find { |t| t["id"] == task.id }

    assert_equal 2, row["available_kit_count"]
  end

  test "show counts what a list workflow still owes its members" do
    workflow = Workflow.where(name: "SameListForEveryone").first_or_create!(user_states: "needs_kit,has_kit")
    Workflow.where(id: workflow.id).update_all(type: "WorkflowSameListForEveryone")
    task = tasks(:alpha_task_one)   # alice and bob are members
    task.update!(workflow: Workflow.find(workflow.id))
    TaskDocid.replace_for(task.id, [ "s3://bucket/one.json", "s3://bucket/two.json" ])
    assert_equal 0, Kit.where(task_id: task.id).count
    sign_in_as @alice

    get project_url(@alpha), as: :json
    row = JSON.parse(@response.body)["tasks"].find { |t| t["id"] == task.id }

    assert_equal 4, row["available_kit_count"], "two documents each, for two members, and no kits yet"
  end

  test "show returns permission-denied for a non-member non-admin" do
    sign_in_as @bob
    get project_url(@beta), as: :json
    body = JSON.parse(@response.body)
    assert_equal "Permission denied.", body["error"]
  end

  test "show marks owner and admin booleans for the owner" do
    sign_in_as @alice
    get project_url(@alpha), as: :json
    body = JSON.parse(@response.body)
    assert_equal true, body["project_owner_bool"]
    assert_equal true, body["project_admin_bool"]
  end

  test "show marks owner/admin booleans false for a plain member" do
    sign_in_as @bob
    get project_url(@alpha), as: :json
    body = JSON.parse(@response.body)
    assert_equal false, body["project_owner_bool"]
    assert_equal false, body["project_admin_bool"]
  end

  # Regression: a Portal Manager isn't the project owner and (usually)
  # isn't a system admin, but SessionsHelper#project_owner? treats them
  # as owner-equivalent. The show action was computing project_owner_bool
  # inline with only `admin?`, so the Svelte "Add Member" button hid for
  # Portal Managers even though the backend would accept the request.
  test "show marks admin/owner booleans true for a portal manager" do
    sign_in_as @pat
    get project_url(@alpha), as: :json
    body = JSON.parse(@response.body)
    assert_equal true, body["project_owner_bool"],
      "Portal Manager should be treated as project owner for the frontend gate"
    assert_equal true, body["project_admin_bool"],
      "Portal Manager should be treated as project admin for the frontend gate"
  end

  # ── create ────────────────────────────────────────────────────────────────

  test "create makes the creator owner+admin" do
    sign_in_as @bob
    assert_difference -> { Project.count }, 1 do
      post projects_url, params: { project: { name: "bob_project" } }, as: :json
    end
    body = JSON.parse(@response.body)
    project = Project.find(body["id"])
    assert project.owner?(@bob)
    assert project.admin?(@bob)
  end

  test "create rejects a duplicate name" do
    sign_in_as @bob
    assert_no_difference -> { Project.count } do
      post projects_url, params: { project: { name: @alpha.name } }, as: :json
    end
    body = JSON.parse(@response.body)
    assert body["error"].present?
  end

  # ── update ────────────────────────────────────────────────────────────────

  test "update allows the project owner" do
    sign_in_as @alice
    patch project_url(@alpha), params: { project: { title: "Renamed Alpha" } }, as: :json
    assert_response :success
    assert_equal "Renamed Alpha", @alpha.reload.title
  end

  test "update blocks a plain member" do
    sign_in_as @bob
    patch project_url(@alpha), params: { project: { title: "Hijacked" } }, as: :json
    assert_redirected_to root_path
    assert_not_equal "Hijacked", @alpha.reload.title
  end

  test "update blocks a non-member" do
    sign_in_as @bob
    patch project_url(@beta), params: { project: { title: "Hijacked" } }, as: :json
    assert_redirected_to root_path
  end

  # ── destroy ───────────────────────────────────────────────────────────────

  test "destroy is admin-only" do
    sign_in_as @bob
    delete project_url(@alpha), as: :json
    # admin_user before_action redirects non-admins
    assert_redirected_to root_path
    assert Project.exists?(@alpha.id)
  end

  test "destroy works for a system admin" do
    sign_in_as @admin
    delete project_url(@beta), as: :json
    assert_response :success
    assert_not Project.exists?(@beta.id)
  end
end
