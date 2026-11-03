require "test_helper"

class ActionsControllerTest < ActionDispatch::IntegrationTest
  test "an action is recorded as the signed-in user's, whatever user_id is sent" do
    task = tasks(:alpha_task_one)
    kit = Kit.create!(task: task, kit_type_id: task.kit_type_id, state: "assigned",
      user: users(:bob), uid: "action-kit-#{SecureRandom.hex(3)}")
    sign_in_as users(:bob)
    post actions_url, params: { user_id: users(:alice).id, task_id: task.id, kit_id: kit.id,
      name: "pressed_play", client_time: 1 }, as: :json
    action = Action.find(JSON.parse(@response.body)["ok"])
    assert_equal users(:bob).id, action.user_id
    assert_equal "pressed_play", action.name
  end
end
