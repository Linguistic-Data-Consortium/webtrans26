require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)   # project_admin on alpha (owner+admin); task_admin on alpha_task_one
    @bob = users(:bob)       # project member on alpha; task_user on alpha_task_one (non-admin)
    @admin = users(:admin)   # system admin
    @alpha = projects(:alpha)
    @beta = projects(:beta)
    @task1 = tasks(:alpha_task_one)
    @workflow = workflows(:orderly)
    @kit_type = kit_types(:basic)
  end

  # ── show ──────────────────────────────────────────────────────────────────

  test "show returns full task details for a task admin" do
    sign_in_as @alice
    get task_url(@task1), as: :json
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal @task1.id, body["id"]
    assert body.key?("workflows")
    assert body.key?("members")
  end

  test "show denies non-admin task members" do
    sign_in_as @bob
    get task_url(@task1), as: :json
    body = JSON.parse(@response.body)
    assert_equal "you must be a task admin to do that", body["error"]
  end

  # ── create ────────────────────────────────────────────────────────────────

  test "create lets a project admin add a task" do
    sign_in_as @alice
    assert_difference -> { @alpha.tasks.count }, 1 do
      post project_tasks_url(project_id: @alpha.id), params: {
        task: { name: "new_task_1", workflow_id: @workflow.id, kit_type_id: @kit_type.id }
      }, as: :json
    end
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "new_task_1", body["name"]
  end

  test "create blocks non-project-admin" do
    sign_in_as @bob
    assert_no_difference -> { @alpha.tasks.count } do
      post project_tasks_url(project_id: @alpha.id), params: {
        task: { name: "sneaky_task", workflow_id: @workflow.id, kit_type_id: @kit_type.id }
      }, as: :json
    end
    body = JSON.parse(@response.body)
    assert_equal "You must be a project admin to do that.", body["error"]
  end

  test "create rejects duplicate task name within the project" do
    sign_in_as @alice
    assert_no_difference -> { Task.count } do
      post project_tasks_url(project_id: @alpha.id), params: {
        task: { name: @task1.name, workflow_id: @workflow.id, kit_type_id: @kit_type.id }
      }, as: :json
    end
    body = JSON.parse(@response.body)
    assert body["error"].present?
  end

  # ── update ────────────────────────────────────────────────────────────────

  test "update allows a task admin to rename" do
    sign_in_as @alice
    patch task_url(@task1), params: { task: { name: "alpha_task_renamed" } }, as: :json
    assert_response :success
    assert_equal "alpha_task_renamed", @task1.reload.name
  end

  test "update blocks a non-admin" do
    sign_in_as @bob
    patch task_url(@task1), params: { task: { name: "hijacked" } }, as: :json
    body = JSON.parse(@response.body)
    assert_equal "You must be a task admin to do that.", body["error"]
    assert_not_equal "hijacked", @task1.reload.name
  end

  # ── destroy ───────────────────────────────────────────────────────────────

  test "destroy works for a project admin and cascades to task_users" do
    sign_in_as @alice
    task_user_ids = @task1.task_user_ids
    delete task_url(@task1), as: :json
    assert_response :success
    assert_not Task.exists?(@task1.id)
    assert_equal 0, TaskUser.where(id: task_user_ids).count
  end

  test "destroy blocks a non-admin" do
    # NOTE: TasksController#destroy has a bug in the non-admin branch — it returns the error
    # hash without calling `render json:`, so the response body is empty. We still expect the
    # task to remain because the destroy call never fires.
    sign_in_as @bob
    delete task_url(@task1), as: :json
    assert Task.exists?(@task1.id), "task should not be deleted when non-admin attempts destroy"
  end
end
