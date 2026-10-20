require "test_helper"

# Adding every member of another task to this one — the "Add Members from Task"
# dialog on the Task Members tab.
#
# Alice owns and admins the alpha project (so she administers every task in
# it); Bob is a plain member of alpha_task_one and of the project.
class TaskUsersCopyTest < ActionDispatch::IntegrationTest
  setup do
    @to = tasks(:alpha_task_two)     # no members in the fixtures
    @from = tasks(:alpha_task_one)   # alice (admin) and bob
    @alice = users(:alice)
    @bob = users(:bob)
  end

  def source_tasks(task_id: @to.id)
    get "/task_users/source_tasks", params: { task_id: task_id }, as: :json
    JSON.parse(@response.body)
  end

  def copy(from: @from.id, to: @to.id)
    post "/task_users/copy_from_task", params: { task_id: to, from_task_id: from }, as: :json
    JSON.parse(@response.body)
  end

  test "the tasks offered are the ones the user administers, without this one" do
    sign_in_as @alice

    body = source_tasks
    names = body.map { |t| t["name"] }

    assert_includes names, @from.name
    assert_not_includes names, @to.name, "copying a task into itself isn't a thing"
    assert_not_includes names, tasks(:beta_task_one).name, "alice doesn't administer the beta project"
    assert_equal 2, body.find { |t| t["name"] == @from.name }["member_count"]
    assert_equal projects(:alpha).name, body.first["project_name"]
  end

  test "it adds every member of the other task" do
    sign_in_as @alice

    body = copy

    assert_equal [ @alice.name, @bob.name ].sort, body["added"].sort
    assert_equal [], body["skipped"]
    assert_equal [ @alice.id, @bob.id ].sort, @to.reload.users.pluck(:id).sort
  end

  test "membership only — an admin of the other task isn't an admin here" do
    sign_in_as @alice
    assert task_users(:alice_admin_alpha_task_one).admin?, "alice admins the task being copied from"

    copy

    assert_equal [ false, false ], TaskUser.by_task(@to.id).pluck(:admin),
      "the same rows Add Member makes, one at a time"
    assert_equal [ nil, nil ], TaskUser.by_task(@to.id).pluck(:state), "their state starts fresh"
  end

  test "someone already a member is left alone, so it can be run again" do
    sign_in_as @alice
    copy

    body = copy

    assert_equal [], body["added"]
    assert_equal [ @alice.name, @bob.name ].sort, body["skipped"].sort
    assert_equal 2, TaskUser.by_task(@to.id).count, "no duplicates"
    assert_match(/0 added/, body["ok"])
  end

  test "a task can't be copied into itself" do
    sign_in_as @alice

    assert_match(/already this task/, copy(from: @to.id)["error"])
  end

  test "an unknown task is an error, not an exception" do
    sign_in_as @alice

    assert_equal "no such task", copy(from: 0)["error"]
  end

  test "someone who doesn't administer the destination can't copy into it" do
    sign_in_as @bob

    assert_match(/permission denied/, copy(to: @from.id, from: @to.id)["error"])
    assert_equal 0, TaskUser.by_task(@to.id).count
  end

  test "a task the user doesn't administer can't be copied from" do
    # Bob admins a task of his own, in a project he doesn't administer, so the
    # destination check passes and the source check is the one that has to bite.
    bobs = Task.create!(
      name: "bobs-task-#{SecureRandom.hex(3)}", project: projects(:beta),
      workflow: workflows(:orderly), kit_type: kit_types(:basic)
    )
    TaskUser.create!(task: bobs, user: @bob, admin: true)
    sign_in_as @bob

    body = copy(to: bobs.id, from: @from.id)

    assert_match(/don't administer #{Regexp.escape(@from.name)}/, body["error"])
    assert_equal [ @bob.id ], bobs.reload.users.pluck(:id)
  end
end
