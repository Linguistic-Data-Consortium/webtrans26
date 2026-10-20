require "test_helper"

# End-to-end flow from a user's perspective:
#   1. Alice signs in and creates a new project (she becomes owner+admin)
#   2. Alice adds Bob to the project as a member
#   3. Alice creates a task in the project
#   4. Alice adds Bob as a task member
#   5. A kit is created for the task
#   6. Bob signs in and starts work on the task -> kit is assigned to him
#   7. Bob's kit is marked done -> task_user returns to needs_kit
class ProjectWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    @bob = users(:bob)
    @workflow = workflows(:orderly)
    @kit_type = kit_types(:basic)
  end

  test "a user can run the full create-project → add-task → assign-user → start-work → complete flow" do
    sign_in_as @alice

    # 1. Create a project as Alice
    assert_difference -> { Project.count }, 1 do
      post projects_url, params: { project: { name: "research_study" } }, as: :json
    end
    assert_response :success
    project_body = JSON.parse(@response.body)
    project_id = project_body["id"]
    assert_equal "research_study", project_body["name"]

    project = Project.find(project_id)
    assert project.owner?(@alice), "creator should be owner"
    assert project.admin?(@alice), "creator should be admin"

    # 2. Add Bob to the project
    assert_difference -> { project.users.count }, 1 do
      post project_users_url, params: { project_id: project.id, user_id: @bob.id }, as: :json
    end
    assert_response :success
    body = JSON.parse(@response.body)
    assert_match(/#{@bob.name} has been added/, body["ok"])
    assert_includes project.reload.users, @bob

    # 3. Create a task in the project
    assert_difference -> { project.tasks.count }, 1 do
      post project_tasks_url(project_id: project.id), params: {
        task: {
          name: "annotate_texts",
          workflow_id: @workflow.id,
          kit_type_id: @kit_type.id
        }
      }, as: :json
    end
    assert_response :success
    task_body = JSON.parse(@response.body)
    task = Task.find(task_body["id"])
    assert_equal "annotate_texts", task.name
    assert_equal project.id, task.project_id
    assert_equal @workflow.id, task.workflow_id

    # 4. Add Bob as a task_user
    assert_difference -> { task.task_users.count }, 1 do
      post task_users_url, params: { task_id: task.id, user_id: @bob.id }, as: :json
    end
    assert_response :success
    body = JSON.parse(@response.body)
    assert_match(/#{@bob.name} has been added/, body["ok"])

    bob_tu = TaskUser.find_by!(task_id: task.id, user_id: @bob.id)

    # 5. Seed a kit for the task. In production, kits are created by kit_batches /
    # file uploads; here we create one directly so the Orderly workflow has something to assign.
    kit = Kit.create!(
      task_id: task.id,
      kit_type_id: @kit_type.id,
      state: "unassigned",
      uid: "kit-#{SecureRandom.hex(4)}",
      tree_id: 1 # any non-nil skips Kit#create_tree, which would need a full class_def graph
    )

    # 6. Bob signs in and starts work. The route path is /workflows/:id/work/:workflow_id
    # where :id is the task_user_id (the controller reads TaskUser.find params[:id]).
    delete session_url
    sign_in_as @bob

    get "/workflows/#{bob_tu.id}/work/#{@workflow.id}"

    # Accept either success (JSON) or redirect-on-error (flash message). We'll be strict on state instead.
    bob_tu.reload
    kit.reload
    assert_equal "has_kit", bob_tu.state, "task_user should transition to has_kit"
    assert_equal "assigned", kit.state, "kit should be assigned"
    assert_equal @bob.id, kit.user_id, "kit should be owned by Bob"
    assert_equal kit.uid, bob_tu.kit_oid, "task_user.kit_oid should point at the assigned kit"

    # 7. Complete the kit. Emulate the workflow's "done" message directly via the state transition.
    kit.update!(state: "done")
    bob_tu.goto_state("needs_kit")

    assert_equal "done", kit.reload.state
    assert_equal "needs_kit", bob_tu.reload.state
    assert_nil Kit.where(task_id: task.id, state: "unassigned").first, "no more unassigned kits remain"
  end
end
