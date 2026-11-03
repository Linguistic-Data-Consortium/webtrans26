require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { ActionMailer::Base.deliveries.clear }

  test "GET /passwords/new (default: mail off) shows the access-link notice and no form" do
    get new_password_path
    assert_response :success
    assert_select "form[action=?]", passwords_path, count: 0
    assert_match(/sign-in link/i, response.body)
  end

  test "GET /passwords/new with mail enabled renders the request-reset form" do
    with_mail_enabled do
      get new_password_path
      assert_response :success
      assert_select "form[action=?]", passwords_path
      assert_select "input[name='email_address']"
    end
  end

  # The mail-off branch used to set the submitted password and deactivate the
  # account: a lockout lever for anyone who knew an address, and a way to choose
  # the password an admin would later reactivate.
  test "POST /passwords (default: mail off) changes nothing, whatever it is sent" do
    alice = users(:alice)
    alice.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    digest = alice.password_digest

    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      post passwords_path, params: {
        email_address: alice.email_address,
        password: "attacker-pw",
        password_confirmation: "attacker-pw"
      }
    end

    alice.reload
    assert alice.activated?
    assert alice.sessions.any?
    assert_equal digest, alice.password_digest
    assert_redirected_to new_session_path
    assert_match(/sign-in link/i, flash[:notice])
  end

  test "POST /passwords with mail enabled and a known email sends a reset email and redirects" do
    with_mail_enabled do
      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        perform_enqueued_jobs { post passwords_path, params: { email_address: users(:alice).email_address } }
      end
      assert_redirected_to new_session_path
      assert_match(/Password reset instructions sent/i, flash[:notice])

      mail = ActionMailer::Base.deliveries.last
      assert_equal [users(:alice).email_address], mail.to
      assert_match(/Reset your password/i, mail.subject)
    end
  end

  # Sent in the background, so a known address answers as fast as an unknown one:
  # the time the request took can't say whether the address has an account.
  test "POST /passwords with mail enabled queues the reset email rather than sending it in the request" do
    with_mail_enabled do
      assert_enqueued_emails 1 do
        assert_no_difference -> { ActionMailer::Base.deliveries.size } do
          post passwords_path, params: { email_address: users(:alice).email_address }
        end
      end
    end
  end

  test "POST /passwords with mail enabled and an unknown email still redirects without sending mail" do
    with_mail_enabled do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        post passwords_path, params: { email_address: "nobody@example.com" }
      end
      assert_redirected_to new_session_path
      assert_match(/Password reset instructions sent/i, flash[:notice])
    end
  end

  # Open the emailed link: it stashes the token and redirects to a URL without it.
  def open_reset_link(token)
    get edit_password_path(token)
    assert_redirected_to reset_password_path
    follow_redirect!
  end

  def submit_reset(password, confirmation = password)
    patch reset_password_path, params: { password: password, password_confirmation: confirmation }
  end

  test "the older link form, /passwords/:token/edit, moves its token out of the URL" do
    open_reset_link(users(:alice).password_reset_token)
    assert_response :success
    assert_select "form[action=?]", reset_password_path
    assert_select "input[name='password']"
    assert_select "input[name='password_confirmation']"
    assert_no_match users(:alice).password_reset_token, response.body
  end

  test "GET /passwords/:token/edit with an invalid token redirects" do
    get edit_password_path("nope-not-a-real-token")
    assert_redirected_to new_password_path
    assert_match(/invalid or has expired/i, flash[:alert])
  end

  test "PATCH /passwords/:token updates the password with a valid token" do
    token = users(:alice).password_reset_token
    open_reset_link(token)
    submit_reset("brand-new-pw", "brand-new-pw")
    assert_redirected_to new_session_path
    assert_match(/updated/i, flash[:notice])

    users(:alice).reload
    assert users(:alice).authenticate("brand-new-pw")
    assert_not users(:alice).authenticate("password123")
  end

  test "PATCH /passwords/:token signs out the account's existing sessions" do
    alice = users(:alice)
    alice.sessions.create!(user_agent: "elsewhere", ip_address: "10.0.0.1")
    open_reset_link(alice.password_reset_token)
    submit_reset("brand-new-pw")
    assert_empty alice.reload.sessions
  end

  test "PATCH /passwords/:token with mismatched confirmation redirects back with alert" do
    token = users(:alice).password_reset_token
    open_reset_link(token)
    submit_reset("brand-new-pw", "different")
    assert_redirected_to reset_password_path
    assert flash[:alert].present?
    assert users(:alice).reload.authenticate("password123"), "password should be unchanged"
  end

  test "PATCH /passwords/:token with too-short password is rejected" do
    token = users(:alice).password_reset_token
    open_reset_link(token)
    submit_reset("short", "short")
    assert_redirected_to reset_password_path
    assert_match(/Password/i, flash[:alert])
    assert users(:alice).reload.authenticate("password123"), "password should be unchanged"
  end

  test "reset token cannot be reused after the password is changed (salt rotates)" do
    token = users(:alice).password_reset_token
    open_reset_link(token)
    submit_reset("brand-new-pw", "brand-new-pw")
    assert_redirected_to new_session_path

    # The reset token is scoped to the old password_salt — after a successful reset the token invalidates.
    get edit_password_path(token)
    assert_redirected_to new_password_path
    assert_match(/invalid or has expired/i, flash[:alert])
  end

  test "a finished reset can't be submitted again from the same browser" do
    open_reset_link(users(:alice).password_reset_token)
    submit_reset("brand-new-pw")
    submit_reset("second-try-pw")
    assert_redirected_to new_password_path
    assert users(:alice).reload.authenticate("brand-new-pw")
  end

  # ── the link as emailed: /passwords/reset#<token> ─────────────────────────

  test "the reset email's link carries the token in the fragment, not the path" do
    with_mail_enabled do
      perform_enqueued_jobs { post passwords_path, params: { email_address: users(:alice).email_address } }
      body = ActionMailer::Base.deliveries.last.body.encoded
      url, fragment = body[%r{\S*/passwords/\S+}].split("#", 2)
      assert_equal "/passwords/reset", URI(url).path, "nothing secret in the path"
      # Tokens embed their expiry, so compare whose it is rather than the string.
      assert_equal users(:alice), User.find_by_password_reset_token(fragment)
    end
  end

  test "with no token held, /passwords/reset is the claim page, not the form" do
    get reset_password_path
    assert_response :success
    assert_select "form[action=?]", claim_password_reset_path
    assert_select "input[name='password']", count: 0
  end

  test "claiming the fragment's token holds it in the session and opens the form" do
    post claim_password_reset_path, params: { token: users(:alice).password_reset_token }
    assert_redirected_to reset_password_path
    follow_redirect!
    assert_select "input[name='password']"
    submit_reset("brand-new-pw")
    assert users(:alice).reload.authenticate("brand-new-pw")
  end

  test "claiming a bad token sends you back to request a new link" do
    post claim_password_reset_path, params: { token: "not-a-token" }
    follow_redirect!
    assert_redirected_to new_password_path
    assert_match(/invalid or has expired/i, flash[:alert])
  end
end

