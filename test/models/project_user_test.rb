require "test_helper"

class ProjectUserTest < ActiveSupport::TestCase
  test "requires project_id and user_id" do
    pu = ProjectUser.new
    assert_not pu.valid?
    assert pu.errors[:project_id].any?
    assert pu.errors[:user_id].any?
  end

  test "a user can only be a member of a project once" do
    dup = ProjectUser.new(project: projects(:alpha), user: users(:bob)) # bob_on_alpha exists
    assert_not dup.valid?
    assert_match(/already a member/, dup.errors[:user_id].join)
  end

  test "the same user may belong to a different project" do
    pu = ProjectUser.new(project: projects(:beta), user: users(:bob))
    assert pu.valid?, pu.errors.full_messages.join(', ')
  end

  test "delegates user_name and project_name" do
    pu = project_users(:alice_owns_alpha)
    assert_equal users(:alice).name, pu.user_name
    assert_equal projects(:alpha).name, pu.project_name
  end

  test "scope by_project_and_user finds the membership" do
    pu = ProjectUser.by_project_and_user(projects(:alpha).id, users(:alice).id).first
    assert_equal project_users(:alice_owns_alpha), pu
  end

  test "scope project_owner returns owner rows" do
    owners = ProjectUser.project_owner(projects(:alpha).id)
    assert_includes owners, project_users(:alice_owns_alpha)
    assert_not_includes owners, project_users(:bob_on_alpha)
  end
end
