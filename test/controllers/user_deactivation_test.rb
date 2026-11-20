require "test_helper"

# Deactivating from the Activations tab: the active-user search behind it, and
# who may deactivate whom (users#active, users#deactivate).
class UserDeactivationTest < ActionDispatch::IntegrationTest
  test "only portal managers and admins can search active users" do
    sign_in_as users(:alice)
    get active_users_url(term: "b"), as: :json
    assert_response :redirect # portal_manager_user turns others away
  end

  test "the search finds active users by name or email, and not inactive ones" do
    sign_in_as users(:pat)
    get active_users_url(term: "BOB"), as: :json
    names = JSON.parse(@response.body)["users"].map { |u| u["name"] }
    assert_includes names, "bob"
    get active_users_url(term: users(:unactivated).email_address), as: :json
    assert_empty JSON.parse(@response.body)["users"]
  end

  test "each row says whether it's you or an admin, so the tab can hold back the button" do
    sign_in_as users(:pat)
    get active_users_url(term: ""), as: :json
    rows = JSON.parse(@response.body)["users"].index_by { |u| u["name"] }
    assert rows[users(:pat).name]["self"]
    assert rows[users(:admin).name]["admin"]
  end

  test "nobody can deactivate their own account" do
    sign_in_as users(:pat)
    patch deactivate_user_url(users(:pat)), as: :json
    assert_response :forbidden
    assert users(:pat).reload.activated?
  end

  test "a % in the search is a character, not a wildcard" do
    sign_in_as users(:pat)
    get active_users_url(term: "%"), as: :json
    assert_empty JSON.parse(@response.body)["users"]
  end
end
