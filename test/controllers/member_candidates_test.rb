require "test_helper"

# The add-member dialogs list everyone not yet in a group, project or task, so
# the list goes only to someone who can add a member there.
class MemberCandidatesTest < ActionDispatch::IntegrationTest
  test "task candidates: refused to a member who isn't the task's admin" do
    sign_in_as users(:bob)
    get users_not_in_task_url(tasks(:alpha_task_one)), params: { term: "" }, as: :json
    assert_response :forbidden
  end

  test "task candidates: listed for the task's admin" do
    sign_in_as users(:alice)
    get users_not_in_task_url(tasks(:alpha_task_one)), params: { term: "" }, as: :json
    assert_response :success
    assert_kind_of Array, JSON.parse(@response.body)
  end

  test "project candidates: refused to a member who isn't the project's admin" do
    sign_in_as users(:bob)
    get users_not_in_project_url(projects(:alpha)), params: { term: "" }, as: :json
    assert_response :forbidden
  end

  test "project candidates: listed for the project's admin" do
    sign_in_as users(:alice)
    get users_not_in_project_url(projects(:alpha)), params: { term: "" }, as: :json
    assert_response :success
  end

  test "group candidates: refused to anyone but an admin" do
    sign_in_as users(:pat)
    get users_not_in_url(groups(:researchers)), params: { term: "" }, as: :json
    assert_response :forbidden

    sign_in_as users(:admin)
    get users_not_in_url(groups(:researchers)), params: { term: "" }, as: :json
    assert_response :success
  end
end
