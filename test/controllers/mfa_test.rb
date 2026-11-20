require "test_helper"

# Two-step sign-in (User::Mfa): off by default, required of everyone when on.
class MfaTest < ActionDispatch::IntegrationTest
  setup { @alice = users(:alice) }

  # A code from a later 30-second step than the one used to enroll, since a
  # code is never accepted twice.
  def next_code(secret)
    ROTP::TOTP.new(secret).at(Time.now + 30)
  end

  def signed_in?
    get user_path(@alice)
    response.successful?
  end

  # ── off (the default) ──────────────────────────────────────────────────

  test "off: an enrolled user signs in with the password alone" do
    enroll_mfa(@alice)
    sign_in_as @alice
    assert_redirected_to root_url
    assert signed_in?
  end

  test "off: the setup page says it isn't turned on" do
    sign_in_as @alice
    get account_mfa_path
    assert_match(/isn't turned on/, response.body)
  end

  # ── on, not yet set up ─────────────────────────────────────────────────

  test "on: a user without an authenticator is sent to set one up, and JSON is refused" do
    with_mfa_enabled do
      sign_in_as @alice
      get user_path(@alice)
      assert_redirected_to account_mfa_path
      get projects_url, as: :json
      assert_response :forbidden
      assert JSON.parse(@response.body)["mfa_setup_required"]
    end
  end

  test "on: setup shows a QR code, refuses a wrong code, and a right one turns it on" do
    with_mfa_enabled do
      sign_in_as @alice
      get account_mfa_path
      assert_select "#mfa-qr img[src^=?]", "data:image/svg+xml;base64,"
      secret = css_select("#mfa-secret").text.delete(" ")

      post account_mfa_path, params: { code: "000000" }
      assert_redirected_to account_mfa_path
      assert_not @alice.reload.mfa_enrolled?

      post account_mfa_path, params: { code: ROTP::TOTP.new(secret).now }
      assert_response :success
      assert_equal User::Mfa::RECOVERY_CODE_COUNT, css_select("#recovery-codes li").size
      assert @alice.reload.mfa_enrolled?
      assert signed_in?
    end
  end

  # ── on, set up ─────────────────────────────────────────────────────────

  test "on: the password alone signs nobody in; the code does" do
    secret, = enroll_mfa(@alice)
    with_mfa_enabled do
      assert_no_difference -> { @alice.sessions.count } do
        sign_in_as @alice
      end
      assert_redirected_to new_session_mfa_path
      assert_not signed_in?

      post session_mfa_path, params: { code: next_code(secret) }
      assert_response :redirect
      assert signed_in?
    end
  end

  test "on: a code can't be used twice" do
    secret, = enroll_mfa(@alice)
    with_mfa_enabled do
      code = next_code(secret)
      sign_in_as @alice
      post session_mfa_path, params: { code: code }
      delete session_url
      sign_in_as @alice
      post session_mfa_path, params: { code: code }
      assert_redirected_to new_session_mfa_path
      assert_not signed_in?
    end
  end

  test "on: a recovery code signs in once" do
    _, codes = enroll_mfa(@alice)
    with_mfa_enabled do
      sign_in_as @alice
      post session_mfa_path, params: { code: codes.first.upcase }
      assert_redirected_to root_url
      delete session_url
      sign_in_as @alice
      post session_mfa_path, params: { code: codes.first }
      assert_redirected_to new_session_mfa_path
      assert_equal User::Mfa::RECOVERY_CODE_COUNT - 1, @alice.reload.recovery_codes_left
    end
  end

  test "on: three wrong codes lock the account, and a right password doesn't reset the count" do
    secret, = enroll_mfa(@alice)
    with_mfa_enabled do
      sign_in_as @alice
      2.times { post session_mfa_path, params: { code: "000000" } }
      sign_in_as @alice # right password again: must not wipe the two failures
      post session_mfa_path, params: { code: "000000" }
      assert_redirected_to new_session_path
      assert_equal SessionsController::FAILED, flash[:alert]
      assert @alice.reload.locked?

      sign_in_as @alice
      assert_redirected_to new_session_path, "locked: not even as far as the code"
    end
  end

  test "on: the step between password and code expires" do
    secret, = enroll_mfa(@alice)
    with_mfa_enabled do
      sign_in_as @alice
      travel 6.minutes do
        post session_mfa_path, params: { code: ROTP::TOTP.new(secret).now }
        assert_redirected_to new_session_path
        assert_not signed_in?
      end
    end
  end

  test "on: the code page can't be reached without the password first" do
    with_mfa_enabled do
      get new_session_mfa_path
      assert_redirected_to new_session_path
    end
  end

  test "on: an access link still asks for the code, then lets a password be chosen" do
    secret, = enroll_mfa(@alice)
    with_mfa_enabled do
      get access_link_path(@alice.id, @alice.create_access_digest(users(:admin).id))
      assert_redirected_to new_session_mfa_path
      assert_not signed_in?

      post session_mfa_path, params: { code: next_code(secret) }
      assert_redirected_to edit_account_password_path
      follow_redirect!
      assert_select "input[name='current_password']", count: 0
    end
  end

  test "on: new recovery codes need a code from the app, not a recovery code" do
    secret, codes = enroll_mfa(@alice)
    with_mfa_enabled do
      sign_in_as @alice
      post session_mfa_path, params: { code: next_code(secret) }

      post account_mfa_recovery_codes_path, params: { code: codes.last }
      assert_redirected_to account_mfa_path
      travel 31.seconds do # past the step already used to sign in
        post account_mfa_recovery_codes_path, params: { code: next_code(secret) }
        assert_response :success
      end
      assert_not @alice.reload.verify_second_factor(codes.last), "the old set is gone"
    end
  end

  test "mfa:reset makes the user set it up again" do
    enroll_mfa(@alice)
    @alice.reset_mfa!
    with_mfa_enabled do
      sign_in_as @alice
      get user_path(@alice)
      assert_redirected_to account_mfa_path
    end
  end
end
