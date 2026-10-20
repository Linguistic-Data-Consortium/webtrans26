require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "requires a name" do
    project = Project.new
    assert_not project.valid?
    assert project.errors[:name].any?
  end

  test "requires unique name case-insensitively" do
    project = Project.new(name: projects(:alpha).name.upcase)
    assert_not project.valid?
    assert project.errors[:name].any?
  end

  test "has members via project_users" do
    assert_includes projects(:alpha).users, users(:alice)
    assert_includes projects(:alpha).users, users(:bob)
    assert_not_includes projects(:beta).users, users(:bob)
  end

  test "member? returns project_user when user is a member" do
    assert projects(:alpha).member?(users(:alice))
    assert_nil projects(:beta).member?(users(:bob))
  end

  test "owner? is true only for the designated owner" do
    assert projects(:alpha).owner?(users(:alice))
    assert_not projects(:alpha).owner?(users(:bob))
  end

  test "admin? is true for admins and owners" do
    assert projects(:alpha).admin?(users(:alice))
    assert_not projects(:alpha).admin?(users(:bob))
  end

  test "delete_user removes membership" do
    project = projects(:alpha)
    assert_difference -> { project.users.count }, -1 do
      project.delete_user(users(:bob))
    end
    assert_not_includes project.reload.users, users(:bob)
  end

  test "users_not_in_project excludes members and includes other activated users" do
    not_in = projects(:beta).users_not_in_project
    assert_not_includes not_in, users(:alice)
    assert_includes not_in, users(:bob)
    assert_not_includes not_in, users(:unactivated)
  end

  test "destroy cascades to project_users and tasks" do
    project = projects(:alpha)
    pu_ids = project.project_user_ids
    task_ids = project.task_ids
    project.destroy
    assert_equal 0, ProjectUser.where(id: pu_ids).count
    assert_equal 0, Task.where(id: task_ids).count
  end
end
