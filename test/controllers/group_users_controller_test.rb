require "test_helper"

class GroupUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)              # system admin — allow(:admin)
    @alice = users(:alice)              # not an admin, not in researchers
    @bob = users(:bob)                  # already in researchers
    @researchers = groups(:researchers)
  end

  test "admin can add a user to a group" do
    sign_in_as @admin
    assert_difference -> { @researchers.users.count }, 1 do
      post group_users_url, params: { group_id: @researchers.id, user_id: @alice.id }, as: :json
    end
    assert_match(/#{@alice.name} has been added/, JSON.parse(@response.body)["ok"])
  end

  test "adding a user who is already in the group is a JSON error, not a duplicate row" do
    sign_in_as @admin
    assert_no_difference -> { @researchers.users.count } do
      post group_users_url, params: { group_id: @researchers.id, user_id: @bob.id }, as: :json
    end
    assert_response :success
    assert_match(/#{@bob.name} is already a member/, JSON.parse(@response.body)["error"])
  end

  # Regression: a request with no user_id used to raise RecordNotFound and
  # return a 404 the dashboard couldn't report.
  test "a missing user_id is a JSON error, not a 404" do
    sign_in_as @admin
    assert_no_difference -> { @researchers.users.count } do
      post group_users_url, params: { group_id: @researchers.id }, as: :json
    end
    assert_response :success
    assert_equal "no such user", JSON.parse(@response.body)["error"]
  end

  test "a non-admin cannot add a user to a group" do
    sign_in_as @alice
    assert_no_difference -> { @researchers.users.count } do
      post group_users_url, params: { group_id: @researchers.id, user_id: @alice.id }, as: :json
    end
    assert_response :forbidden
    assert_equal "Permission denied.", JSON.parse(@response.body)["error"]
  end

  test "admin can remove a user from a group" do
    sign_in_as @admin
    gu = group_users(:bob_in_researchers)
    assert_difference -> { @researchers.users.count }, -1 do
      delete group_user_url(gu), as: :json
    end
    assert_match(/#{@bob.name} has been removed/, JSON.parse(@response.body)["ok"])
  end
end
