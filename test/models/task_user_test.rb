require "test_helper"

class TaskUserTest < ActiveSupport::TestCase
  test "requires task_id and user_id" do
    tu = TaskUser.new
    assert_not tu.valid?
    assert tu.errors[:task_id].any?
    assert tu.errors[:user_id].any?
  end

  test "a user can only be a member of a task once" do
    dup = TaskUser.new(task: tasks(:alpha_task_one), user: users(:bob)) # bob_on_alpha_task_one exists
    assert_not dup.valid?
    assert_match(/already a member/, dup.errors[:user_id].join)
  end

  test "the same user may belong to a different task" do
    tu = TaskUser.new(task: tasks(:alpha_task_two), user: users(:bob))
    assert tu.valid?, tu.errors.full_messages.join(', ')
  end

  test "delegates user_name and task_name" do
    tu = task_users(:alice_admin_alpha_task_one)
    assert_equal users(:alice).name, tu.user_name
    assert_equal tasks(:alpha_task_one).name, tu.task_name
  end

  test "project is reached via task" do
    tu = task_users(:alice_admin_alpha_task_one)
    assert_equal projects(:alpha), tu.project
    assert_equal projects(:alpha).id, tu.project_id
  end

  test "goto_state updates state and records a transition after a prior state exists" do
    tu = task_users(:bob_on_alpha_task_one)
    TaskUserState.create!(task_user_id: tu.id, state: tu.state)
    assert_difference -> { tu.task_user_states.count }, 1 do
      tu.goto_state("has_kit")
    end
    assert_equal "has_kit", tu.reload.state
    assert_equal "has_kit", tu.task_user_states.last.state
  end

  test "project_admin? reflects project_user admin/owner flags" do
    alice_tu = task_users(:alice_admin_alpha_task_one)
    assert alice_tu.project_admin?

    bob_tu = task_users(:bob_on_alpha_task_one)
    assert_not bob_tu.project_admin?
  end

  test "system_admin? reflects underlying user.admin?" do
    assert_not task_users(:alice_admin_alpha_task_one).system_admin?
    admin_tu = TaskUser.create!(task: tasks(:alpha_task_two), user: users(:admin), state: "needs_kit")
    assert admin_tu.system_admin?
  end

  test "has_kit_oid? is false when kit_oid is blank" do
    tu = task_users(:alice_admin_alpha_task_one)
    assert_not tu.has_kit_oid?
    tu.update!(kit_oid: "abc-123")
    assert tu.has_kit_oid?
  end

  test "scope by_task_and_user returns the expected row" do
    tu = TaskUser.by_task_and_user(tasks(:alpha_task_one).id, users(:alice).id).first
    assert_equal task_users(:alice_admin_alpha_task_one), tu
  end
end
