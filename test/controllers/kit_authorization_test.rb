require "test_helper"

# Who may read and change a kit. Every endpoint here used to answer any
# signed-in user about any kit, so each test asks as someone who shouldn't get
# in, and where it matters as someone who should.
#
#   alice    admin of alpha_task_one (and owner of project alpha)
#   bob      ordinary member of alpha_task_one
#   charlie  in no task at all
class KitAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    @bob = users(:bob)
    @charlie = users(:charlie)
    @task = tasks(:alpha_task_one)
    @kit = Kit.create!(task_id: @task.id, kit_type_id: @task.kit_type_id,
      state: "unassigned", uid: "authz-kit-#{SecureRandom.hex(3)}")
  end

  # ── reads ────────────────────────────────────────────────────────────────

  test "undo: a stranger is refused the annotation log" do
    sign_in_as @charlie
    get "/kits/#{@kit.id}/undo", as: :json
    assert_response :forbidden
  end

  test "undo: a task member is refused a kit that isn't theirs" do
    sign_in_as @bob
    get "/kits/#{@kit.id}/undo", as: :json
    assert_response :forbidden
  end

  test "undo: the kit's holder and the task admin can read it" do
    @kit.update!(user_id: @bob.id)
    sign_in_as @bob
    get "/kits/#{@kit.id}/undo", as: :json
    assert_response :success

    sign_in_as @alice
    get "/kits/#{@kit.id}/undo", as: :json
    assert_response :success
  end

  test "undo: holding a kit through kit_oid counts, with user_id empty" do
    task_users(:bob_on_alpha_task_one).update!(kit_oid: @kit.uid, state: "has_kit")
    sign_in_as @bob
    get "/kits/#{@kit.id}/undo", as: :json
    assert_response :success
  end

  test "get: task_user_id=readonly no longer opens any kit" do
    sign_in_as @charlie
    get "/kits/get", params: { uid: @kit.uid, task_user_id: "readonly" }, as: :json
    assert_response :forbidden
  end

  test "imported: a stranger is refused" do
    sign_in_as @charlie
    post "/kits/imported", params: { uid: @kit.uid }, as: :json
    assert_response :forbidden
  end

  test "check: a stranger is refused" do
    sign_in_as @charlie
    get "/kits/#{@kit.id}/check", as: :json
    assert_response :forbidden
  end

  test "all: a task member who isn't its admin can't download every transcript" do
    sign_in_as @bob
    get "/kits/all", params: { task_id: @task.id }, as: :json
    assert_response :forbidden
  end

  test "all: the task admin can" do
    sign_in_as @alice
    get "/kits/all", params: { task_id: @task.id }, as: :json
    assert_response :success
  end

  test "read_only page: a stranger is sent away" do
    sign_in_as @charlie
    get "/workflows/#{workflows(:orderly).id}/read_only/#{@kit.uid}"
    assert_redirected_to root_path
  end

  # ── writes ───────────────────────────────────────────────────────────────

  test "change_time_spent: a stranger can't rewrite it, and GET no longer routes" do
    @kit.update!(time_spent: 5)
    sign_in_as @charlie
    post change_time_spent_kits_path, params: { uid: @kit.uid, time_spent: 0 }, as: :json
    assert_response :forbidden
    assert_equal 5, @kit.reload.time_spent

    get change_time_spent_kits_path, params: { uid: @kit.uid, time_spent: 0 }
    assert_response :not_found
  end

  test "update: tree_id and task_id are not accepted, even from the task admin" do
    other = tasks(:beta_task_one)
    sign_in_as @alice
    patch "/kits/#{@kit.id}/update", params: { kit: { task_id: other.id, tree_id: 999_999 } }, as: :json
    @kit.reload
    assert_equal @task.id, @kit.task_id
    assert_nil @kit.tree_id
  end

  test "update: the kit can't be given to someone outside the task" do
    sign_in_as @alice
    patch "/kits/#{@kit.id}/update", params: { kit: { user_id: @charlie.id } }, as: :json
    assert_match(/isn't a member/, JSON.parse(@response.body)["error"])
    assert_nil @kit.reload.user_id
  end

  test "reassign_many_kits: kits outside the URL's task are left alone" do
    elsewhere = Kit.create!(task_id: tasks(:beta_task_one).id, kit_type_id: @task.kit_type_id,
      state: "unassigned", uid: "authz-other-#{SecureRandom.hex(3)}")
    sign_in_as @alice
    patch "/projects/#{@task.project_id}/tasks/#{@task.id}/reassign_many_kits",
      params: { uids: elsewhere.uid, new_state: "done" }, as: :json
    assert_equal "unassigned", elsewhere.reload.state
  end

  test "kits_new goto: a member can't take someone else's kit" do
    @kit.update!(user_id: @alice.id, state: "assigned")
    sign_in_as @bob
    post "/kits_new", params: { goto: @kit.id }, as: :json
    assert_response :forbidden
    assert_equal @alice.id, @kit.reload.user_id
  end

  test "kits_new: a stranger can't make kits in a task, and GET no longer routes" do
    sign_in_as @charlie
    assert_no_difference -> { Kit.count } do
      post "/kits_new", params: { s3: "s3://b/x.wav", task_id: @task.id, filename: "x.wav" }, as: :json
    end
    assert_response :forbidden

    get "/kits_new", params: { goto: @kit.id }
    assert_response :not_found
  end

  test "kits_new: a task member can still make a kit from a file" do
    sign_in_as @bob
    assert_difference -> { Kit.count }, 1 do
      post "/kits_new", params: { s3: "s3://b/x.wav", task_id: @task.id, filename: "x.wav" }, as: :json
    end
    assert_response :success
  end

  # ── removed endpoints ────────────────────────────────────────────────────

  test "file_upload, reassign_kit, kit_creator and add_user_to_project_and_task are gone" do
    sign_in_as @charlie
    post "/projects/#{@task.project_id}/tasks/#{@task.id}/file_upload"
    assert_response :not_found
    get "/projects/#{@task.project_id}/tasks/#{@task.id}/reassign_kit", params: { kit: @kit.uid }
    assert_response :not_found
    get "/projects/#{@task.project_id}/tasks/#{@task.id}/kit_creator"
    assert_response :not_found
    post "/add_user_to_project_and_task/#{@task.project_id}/#{@task.id}"
    assert_response :not_found
    assert_not @task.reload.member?(@charlie)
  end
end
