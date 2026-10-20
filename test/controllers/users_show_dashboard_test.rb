require "test_helper"

# Focused tests for the JSON payload that drives the users.svelte dashboard.
class UsersShowDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    @bob = users(:bob)
    @admin = users(:admin)
  end

  test "unauthenticated request redirects to sign-in" do
    get user_url(@alice), as: :json
    assert_redirected_to new_session_path
  end

  test "alice loading her own dashboard gets the full JSON payload" do
    sign_in_as @alice
    get user_url(@alice), as: :json
    assert_response :success

    body = JSON.parse(@response.body)
    %w[authenticated user admin portal_manager project_manager tus links bucket_test extra].each do |key|
      assert body.key?(key), "dashboard payload should include '#{key}'"
    end
    assert body["authenticated"] # authenticated? returns the Session object, not a bare true
    assert_equal @alice.name, body["user"]
    assert_equal false, body["admin"]
    assert_equal false, body["project_manager"]
  end

  test "admin loading their own dashboard reports admin: true" do
    sign_in_as @admin
    get user_url(@admin), as: :json
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal true, body["admin"]
  end

  test "alice cannot view bob's dashboard" do
    sign_in_as @alice
    get user_url(@bob), as: :json
    assert_redirected_to root_path
    assert_match(/can.?t access other users/i, flash[:error])
  end

  test "admin also cannot view another user's dashboard" do
    sign_in_as @admin
    get user_url(@alice), as: :json
    assert_redirected_to root_path
    assert_match(/can.?t access other users/i, flash[:error])
  end

  test "tus contains an entry for each of the user's active task_users" do
    sign_in_as @alice
    get user_url(@alice), as: :json

    body = JSON.parse(@response.body)
    task_names = body["tus"].map { |t| t["task"] }
    assert_includes task_names, tasks(:alpha_task_one).name
  end

  test "tus entry exposes project_id/task_id when the user is a task admin" do
    sign_in_as @alice
    get user_url(@alice), as: :json

    body = JSON.parse(@response.body)
    entry = body["tus"].find { |t| t["task"] == tasks(:alpha_task_one).name }
    assert_not_nil entry
    assert_equal projects(:alpha).id, entry["project_id"]
    assert_equal tasks(:alpha_task_one).id, entry["task_id"]
  end

  test "tus entry hides project_id/task_id (zero) for a plain task member" do
    # Bob is a task member on alpha_task_one but not admin, and not a project admin.
    sign_in_as @bob
    get user_url(@bob), as: :json

    body = JSON.parse(@response.body)
    entry = body["tus"].find { |t| t["task"] == tasks(:alpha_task_one).name }
    assert_not_nil entry
    assert_equal 0, entry["project_id"]
    assert_equal 0, entry["task_id"]
  end

  test "links map task_user ids to their workflow/work URL" do
    sign_in_as @alice
    get user_url(@alice), as: :json

    body = JSON.parse(@response.body)
    tu = task_users(:alice_admin_alpha_task_one)
    assert_equal "/workflows/#{tu.task.workflow_id}/work/#{tu.id}", body["links"][tu.id.to_s]
  end

  test "tus entries include an action string ('No Available Kits' when no kits exist)" do
    sign_in_as @alice
    get user_url(@alice), as: :json

    body = JSON.parse(@response.body)
    entry = body["tus"].find { |t| t["task"] == tasks(:alpha_task_one).name }
    assert_equal "No Available Kits", entry["action"]
  end
end
