require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "requires a name" do
    task = Task.new(project: projects(:alpha), workflow: workflows(:orderly), kit_type: kit_types(:basic))
    assert_not task.valid?
    assert task.errors[:name].any?
  end

  test "requires unique name case-insensitively" do
    dup = Task.new(
      name: tasks(:alpha_task_one).name.upcase,
      project: projects(:alpha),
      workflow: workflows(:orderly),
      kit_type: kit_types(:basic)
    )
    assert_not dup.valid?
    assert dup.errors[:name].any?
  end

  test "belongs_to project, workflow, kit_type" do
    task = tasks(:alpha_task_one)
    assert_equal projects(:alpha), task.project
    assert_equal workflows(:orderly), task.workflow
    assert_equal kit_types(:basic), task.kit_type
  end

  test "member? returns task_user when user is assigned to the task" do
    assert tasks(:alpha_task_one).member?(users(:alice))
    assert_nil tasks(:beta_task_one).member?(users(:bob))
  end

  test "admin? is true for admin task_user" do
    assert tasks(:alpha_task_one).admin?(users(:alice))
    assert_not tasks(:alpha_task_one).admin?(users(:bob))
  end

  test "name_with_project is formatted id - project - task" do
    task = tasks(:alpha_task_one)
    assert_equal "#{task.id} - alpha_project - alpha_task_one", task.name_with_project
  end

  test "destroy cascades to task_users" do
    task = tasks(:alpha_task_one)
    tu_ids = task.task_user_ids
    assert_not_equal 0, tu_ids.size
    task.destroy
    assert_equal 0, TaskUser.where(id: tu_ids).count
  end

  test "delete_user removes membership" do
    task = tasks(:alpha_task_one)
    assert_difference -> { task.users.count }, -1 do
      task.delete_user(users(:bob))
    end
  end
end
