require "test_helper"

class FixturesSmokeTest < ActiveSupport::TestCase
  test "fixtures load" do
    assert users(:alice).activated?
    assert_not users(:unactivated).activated?
    assert users(:admin).admin?

    assert_equal "alpha_project", projects(:alpha).name
    assert_equal projects(:alpha), tasks(:alpha_task_one).project
    assert_equal workflows(:orderly), tasks(:alpha_task_one).workflow
    assert_equal kit_types(:basic), tasks(:alpha_task_one).kit_type

    assert_equal users(:alice), project_users(:alice_owns_alpha).user
    assert_equal users(:alice), task_users(:alice_admin_alpha_task_one).user
  end
end
