require "test_helper"

class GroupUserTest < ActiveSupport::TestCase
  test "requires group_id and user_id" do
    gu = GroupUser.new
    assert_not gu.valid?
    assert gu.errors[:group_id].any?
    assert gu.errors[:user_id].any?
  end

  test "a user can only be a member of a group once" do
    dup = GroupUser.new(group: groups(:researchers), user: users(:bob)) # bob_in_researchers exists
    assert_not dup.valid?
    assert_match(/already a member/, dup.errors[:user_id].join)
  end

  test "the same user may belong to a different group" do
    gu = GroupUser.new(group: groups(:project_managers), user: users(:bob))
    assert gu.valid?, gu.errors.full_messages.join(', ')
  end

  test "Group#member? finds the membership" do
    assert groups(:researchers).member?(users(:bob))
    assert_not groups(:researchers).member?(users(:alice))
  end

  test "delegates user_name and group_name" do
    gu = group_users(:bob_in_researchers)
    assert_equal users(:bob).name, gu.user_name
    assert_equal groups(:researchers).name, gu.group_name
  end
end
