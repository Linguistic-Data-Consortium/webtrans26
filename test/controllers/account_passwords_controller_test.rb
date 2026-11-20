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
    body = change(current: "password123", password: GOOD_PASSWORD)
    assert_match(/has been changed/, body["ok"])
    assert @alice.reload.authenticate(GOOD_PASSWORD), "the new password works"
    assert_not @alice.authenticate("password123"), "the old one doesn't"
  end

  test "the wrong current password changes nothing" do
    sign_in_as @alice
    body = change(current: "not-my-password", password: GOOD_PASSWORD)
    assert_equal "Your current password is not correct.", body["error"]
    assert @alice.reload.authenticate("password123")
  end

  test "a new password that breaks the policy is refused, with every reason" do
    sign_in_as @alice
    body = change(current: "password123", password: "alicepassword")
    assert_includes body["errors"], "Password must be at least 16 characters"
    assert_includes body["errors"], %(Password must not contain a common word or pattern ("password"))
    assert_includes body["errors"], "Password must not contain your username or email address"
    assert @alice.reload.authenticate("password123")
  end

  test "a mismatched confirmation is refused" do
    sign_in_as @alice
    body = change(current: "password123", password: GOOD_PASSWORD, confirmation: OTHER_GOOD_PASSWORD)
    assert_match(/don't match/, body["error"])
    assert @alice.reload.authenticate("password123")
  end

  test "other sessions are signed out and this one survives" do
    other = @alice.sessions.create!(user_agent: "phone", ip_address: "10.0.0.1")
    sign_in_as @alice
    this_session_id = @alice.sessions.order(:created_at).last.id

    body = change(current: "password123", password: GOOD_PASSWORD)
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
    body = change(current: "password123", password: GOOD_PASSWORD)
    assert_equal "Your password has been changed.", body["ok"]
  end

  test "a signed-out visitor cannot change a password" do
    patch account_password_url, params: {
      current_password: "password123", password: GOOD_PASSWORD, password_confirmation: GOOD_PASSWORD
    }, as: :json
    assert_response :unauthorized # signed-out JSON gets a 401, not a redirect to the HTML form
    assert users(:alice).reload.authenticate("password123")
  end

  # ── expired passwords ───────────────────────────────────────────────────

  test "an expired password sends every page to the change form" do
    @alice.update_columns(password_changed_at: (User.password_max_age + 1.day).ago)
    sign_in_as @alice
    get user_path(@alice)
    assert_redirected_to edit_account_password_path
    follow_redirect!
    assert_response :success
    assert_select "input[name='current_password']"
    assert_match(/more than #{User.password_max_age.in_days.to_i} days old/, response.body)
  end

  test "an account whose password was never chosen is sent there too" do
    @alice.update_columns(password_changed_at: nil)
    sign_in_as @alice
    get user_path(@alice)
    assert_redirected_to edit_account_password_path
  end

  test "an expired password gets JSON requests a 403 that says why" do
    @alice.update_columns(password_changed_at: nil)
    sign_in_as @alice
    get projects_url, as: :json
    assert_response :forbidden
    assert JSON.parse(@response.body)["password_expired"]
  end

  test "choosing a new password on the form lets the user back in" do
    @alice.update_columns(password_changed_at: nil)
    sign_in_as @alice
    patch account_password_url, params: { current_password: "password123",
      password: GOOD_PASSWORD, password_confirmation: GOOD_PASSWORD }
    assert_redirected_to root_path
    assert_not @alice.reload.password_expired?
    get user_path(@alice)
    assert_response :success
  end

  test "a refused password on the form says why and stays on the form" do
    @alice.update_columns(password_changed_at: nil)
    sign_in_as @alice
    patch account_password_url, params: { current_password: "password123",
      password: "short", password_confirmation: "short" }
    assert_redirected_to edit_account_password_path
    assert_match(/at least 16 characters/, flash[:alert])
  end

  test "after an access link, a password is chosen without the old one" do
    user = users(:unactivated)
    token = user.create_access_digest(users(:admin).id)
    get access_link_path(user.id, token)
    assert_redirected_to edit_account_password_path
    follow_redirect!
    assert_select "input[name='current_password']", count: 0

    patch account_password_url, params: { password: GOOD_PASSWORD, password_confirmation: GOOD_PASSWORD }
    assert_redirected_to root_path
    assert user.reload.authenticate(GOOD_PASSWORD)

    # Only once: the next change asks for the current password again.
    get edit_account_password_path
    assert_select "input[name='current_password']"
  end
end

