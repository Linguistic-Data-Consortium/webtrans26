require "test_helper"

class ActionsControllerTest < ActionDispatch::IntegrationTest
  test "POST /actions logs an event for the current user" do
    # Action belongs_to :user/:task/:kit (all required by default), so we need a real kit.
    kit = Kit.create!(
      task_id: tasks(:alpha_task_one).id,
      kit_type_id: tasks(:alpha_task_one).kit_type_id,
      state: "unassigned",
      uid: "action-kit-#{SecureRandom.hex(3)}"
    )
    sign_in_as users(:alice)

    assert_difference -> { Action.count }, 1 do
      post actions_url, params: {
        user_id: users(:alice).id,
        task_id: tasks(:alpha_task_one).id,
        kit_id: kit.id,
        name: "click_start",
        client_time: 1_700_000_000_000
      }, as: :json
    end

    assert_response :success
    body = JSON.parse(@response.body)
    a = Action.find(body["ok"])
    assert_equal "click_start", a.name
    assert_equal users(:alice).id, a.user_id
    assert_equal tasks(:alpha_task_one).id, a.task_id
    assert_equal kit.id, a.kit_id
    assert_equal 1_700_000_000_000, a.client_time
  end

  test "POST /actions returns ok-but-no-id when required associations are missing" do
    # NOTE: ActionsController#create calls `@action.save` without checking the result and
    # always renders `{ ok: @action.id }`. With missing associations the save fails silently
    # and `@action.id` is nil. Pinning this behavior so a future fix shows up as a regression.
    sign_in_as users(:alice)
    assert_no_difference -> { Action.count } do
      post actions_url, params: { name: "no_assoc" }, as: :json
    end
    assert_response :success
    assert_nil JSON.parse(@response.body)["ok"]
  end

  test "POST /actions requires authentication" do
    assert_no_difference -> { Action.count } do
      post actions_url, params: { name: "click_start" }, as: :json
    end
    assert_redirected_to new_session_path
  end
end
