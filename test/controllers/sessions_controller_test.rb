require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "GET /session/new renders the sign-in form" do
    get new_session_path
    assert_response :success
    assert_select "form[action=?]", session_path
    assert_select "input[name='email_address']"
    assert_select "input[name='password']"
  end

  test "POST /session signs in an activated user and sets the session cookie" do
    assert_difference -> { users(:alice).sessions.count }, 1 do
      sign_in_as users(:alice)
    end
    assert_redirected_to root_url
    assert cookies[:session_id].present?
  end

  test "POST /session rejects wrong password" do
    post session_url, params: { email_address: users(:alice).email_address, password: "wrong-password" }
    assert_redirected_to new_session_path
    assert_match(/Try another email address or password/i, flash[:alert])
    assert cookies[:session_id].blank?
  end

  test "POST /session blocks unactivated users" do
    post session_url, params: { email_address: users(:unactivated).email_address, password: "password123" }
    assert_redirected_to new_session_path
    assert_match(/hasn.?t been activated/i, flash[:alert])
  end

  test "DELETE /session terminates the session" do
    sign_in_as users(:alice)
    assert cookies[:session_id].present?

    assert_difference -> { Session.count }, -1 do
      delete session_url
    end
    assert_redirected_to new_session_path
    assert cookies[:session_id].blank?
  end

end
