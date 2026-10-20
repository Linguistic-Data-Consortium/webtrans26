require "test_helper"

class TaskUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)       # project owner+admin, task admin
    @bob = users(:bob)           # project member, task member (non-admin)
    @charlie = users(:charlie)   # not a member of anything
    @task1 = tasks(:alpha_task_one)
    @task2 = tasks(:alpha_task_two)
  end

  # ── create ────────────────────────────────────────────────────────────────

  test "task admin can add a user to the task" do
    sign_in_as @alice
    assert_difference -> { @task2.task_users.count }, 1 do
      post task_users_url, params: { task_id: @task2.id, user_id: @charlie.id }, as: :json
    end
    body = JSON.parse(@response.body)
    assert_match(/#{@charlie.name} has been added/, body["ok"])
  end

  test "non-admin member cannot add a user to a task" do
    sign_in_as @bob
    assert_no_difference -> { @task1.task_users.count } do
      post task_users_url, params: { task_id: @task1.id, user_id: @charlie.id }, as: :json
    end
    body = JSON.parse(@response.body)
    assert_equal "permission denied", body["error"]
  end

  test "adding a user who is already on the task is a JSON error, not a duplicate row" do
    sign_in_as @alice
    assert_no_difference -> { @task1.task_users.count } do
      post task_users_url, params: { task_id: @task1.id, user_id: @bob.id }, as: :json
    end
    assert_response :success
    assert_match(/#{@bob.name} is already a member/, JSON.parse(@response.body)["error"])
  end

  # Regression: a request with no user_id used to raise RecordNotFound and
  # return a 404 the dashboard couldn't report.
  test "a missing user_id is a JSON error, not a 404" do
    sign_in_as @alice
    assert_no_difference -> { @task1.task_users.count } do
      post task_users_url, params: { task_id: @task1.id }, as: :json
    end
    assert_response :success
    assert_equal "no such user", JSON.parse(@response.body)["error"]
  end

  # ── destroy ───────────────────────────────────────────────────────────────

  test "task admin can remove a user from the task" do
    sign_in_as @alice
    tu = task_users(:bob_on_alpha_task_one)
    assert_difference -> { @task1.task_users.count }, -1 do
      delete task_user_url(tu), as: :json
    end
    body = JSON.parse(@response.body)
    assert_match(/#{@bob.name} has been removed/, body["ok"])
  end

  test "non-admin cannot remove a user" do
    sign_in_as @bob
    tu = task_users(:alice_admin_alpha_task_one)
    assert_no_difference -> { @task1.task_users.count } do
      delete task_user_url(tu), as: :json
    end
    body = JSON.parse(@response.body)
    assert_equal "permission denied", body["error"]
  end

  # ── update (toggle admin flag, change state) ──────────────────────────────

  test "task admin can promote a task_user to admin" do
    sign_in_as @alice
    tu = task_users(:bob_on_alpha_task_one)
    assert_not tu.admin?
    patch task_user_url(tu), params: { admin: true }, as: :json
    assert_response :success
    assert tu.reload.admin?
  end

  test "task admin can change a task_user's state" do
    sign_in_as @alice
    tu = task_users(:bob_on_alpha_task_one)
    patch task_user_url(tu), params: { state: "hold" }, as: :json
    assert_response :success
    assert_equal "hold", tu.reload.state
  end

  test "non-admin cannot change another task_user's admin or state" do
    sign_in_as @bob
    tu = task_users(:alice_admin_alpha_task_one)
    patch task_user_url(tu), params: { admin: false, state: "hold" }, as: :json
    body = JSON.parse(@response.body)
    assert_equal "permission denied", body["error"]
    assert tu.reload.admin?
    assert_not_equal "hold", tu.state
  end
end
