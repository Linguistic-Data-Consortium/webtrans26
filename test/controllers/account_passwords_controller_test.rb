require "test_helper"

class AccountPasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice) # fixture password is "password123"
  end

  def change(current:, password:, confirmation: nil)
    patch account_password_url, params: {
      current_password: current,
      password: password,
      password_confirmation: confirmation.nil? ? password : confirmation
    }, as: :json
    JSON.parse(@response.body)
  end

  test "a signed-in user can change their own password" do
    sign_in_as @alice
    body = change(current: "password123", password: "newpassword1")
    assert_match(/has been changed/, body["ok"])
    assert @alice.reload.authenticate("newpassword1"), "the new password works"
    assert_not @alice.authenticate("password123"), "the old one doesn't"
  end

  test "the wrong current password changes nothing" do
    sign_in_as @alice
    body = change(current: "not-my-password", password: "newpassword1")
    assert_equal "Your current password is not correct.", body["error"]
    assert @alice.reload.authenticate("password123")
  end

  test "a new password under 8 characters is refused" do
    sign_in_as @alice
    body = change(current: "password123", password: "short")
    assert_match(/at least 8/, body["error"])
    assert @alice.reload.authenticate("password123")
  end

  test "a mismatched confirmation is refused" do
    sign_in_as @alice
    body = change(current: "password123", password: "newpassword1", confirmation: "newpassword2")
    assert_match(/don't match/, body["error"])
    assert @alice.reload.authenticate("password123")
  end

  test "other sessions are signed out and this one survives" do
    other = @alice.sessions.create!(user_agent: "phone", ip_address: "10.0.0.1")
    sign_in_as @alice
    this_session_id = @alice.sessions.order(:created_at).last.id

    body = change(current: "password123", password: "newpassword1")
    assert_match(/Signed out 1 other session\./, body["ok"])
    assert_not Session.exists?(other.id), "the other device is gone"
    assert Session.exists?(this_session_id), "the current browser stays signed in"

    # still authenticated afterwards: root sends a signed-in user to their
    # dashboard, where a signed-out one would be sent to the sign-in page.
    get root_path
    assert_redirected_to user_path(@alice)
  end

  test "the message says nothing about other sessions when there are none" do
    sign_in_as @alice
    @alice.sessions.where.not(id: @alice.sessions.order(:created_at).last.id).destroy_all
    body = change(current: "password123", password: "newpassword1")
    assert_equal "Your password has been changed.", body["ok"]
  end

  test "a signed-out visitor cannot change a password" do
    patch account_password_url, params: {
      current_password: "password123", password: "newpassword1", password_confirmation: "newpassword1"
    }, as: :json
    assert_redirected_to new_session_path
    assert users(:alice).reload.authenticate("password123")
  end
end
