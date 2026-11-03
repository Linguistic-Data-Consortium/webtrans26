require "test_helper"

# The test environment turns forgery protection off. These tests turn it back
# on, so they see what a browser would: a cookie-authenticated write without the
# page's token is refused, and the same write with it goes through.
class CsrfProtectionTest < ActionDispatch::IntegrationTest
  setup do
    @was = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @task = tasks(:alpha_task_one)
    sign_in_with_token users(:alice) # admin of alpha_task_one
  end

  teardown { ActionController::Base.allow_forgery_protection = @was }

  # Signing in is itself a protected POST, so take the token off the form first.
  def sign_in_with_token(user)
    get new_session_url
    post session_url, params: { email_address: user.email_address, password: "password123",
      authenticity_token: token_on_page }
    follow_redirect!
  end

  def token_on_page
    response.body[/name="csrf-token" content="([^"]+)"/, 1] ||
      response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  test "replacing a task's docid list needs the token" do
    post "/task_docids", params: { task_id: @task.id, docids: [ "a.wav" ] }, as: :json
    assert_response :unprocessable_content
    assert_empty TaskDocid.where(task_id: @task.id)

    get user_path(users(:alice))
    post "/task_docids", params: { task_id: @task.id, docids: [ "a.wav" ] }, as: :json,
      headers: { "X-CSRF-Token" => token_on_page }
    assert_response :success
  end

  test "making kits from the kits tab needs the token" do
    assert_no_difference -> { Kit.count } do
      post "/create_kits_from_kits_tab", params: { task_id: @task.id, kits: [ { docid: "x.wav" } ] }, as: :json
    end
    assert_response :unprocessable_content
  end

  test "asking for Cognito credentials needs the token" do
    post "/token", as: :json
    assert_response :unprocessable_content
  end
end
