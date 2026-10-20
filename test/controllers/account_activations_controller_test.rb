require "test_helper"

class AccountActivationsControllerTest < ActionDispatch::IntegrationTest
  # The fixture user has `activation_digest` set to nil, so we build a fresh user via the
  # model's `before_create :create_activation_digest` callback to get a matching digest/token pair.
  def create_pending_user
    user = User.create!(
      name: "pending_u",
      email_address: "pending_u@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    user.update_columns(activated: false, activated_at: nil, confirmed_at: nil)
    user
  end

  test "valid token and matching email activates the user" do
    user = create_pending_user
    assert_not user.activated?

    get edit_account_activation_path(user.activation_token, email: user.email_address)
    assert_redirected_to root_url

    user.reload
    assert user.activated?
    assert_not_nil user.activated_at
    assert_match(/Account activated/i, flash[:success])
  end

  test "already-activated user is told so and stays activated" do
    user = create_pending_user
    user.activate
    original_activated_at = user.activated_at

    get edit_account_activation_path(user.activation_token, email: user.email_address)
    assert_redirected_to root_url
    assert_match(/Already activated/i, flash[:success])
    assert_equal original_activated_at.to_i, user.reload.activated_at.to_i
  end

  test "invalid token rejects activation" do
    user = create_pending_user

    get edit_account_activation_path("totally-wrong-token", email: user.email_address)
    assert_redirected_to root_url
    assert_match(/Invalid activation link/i, flash[:danger])
    assert_not user.reload.activated?
  end

  test "unknown email rejects activation" do
    user = create_pending_user

    get edit_account_activation_path(user.activation_token, email: "stranger@example.com")
    assert_redirected_to root_url
    assert_match(/Invalid activation link/i, flash[:danger])
    assert_not user.reload.activated?
  end

  test "missing email param rejects activation" do
    user = create_pending_user

    get edit_account_activation_path(user.activation_token)
    assert_redirected_to root_url
    assert_match(/Invalid activation link/i, flash[:danger])
    assert_not user.reload.activated?
  end
end
