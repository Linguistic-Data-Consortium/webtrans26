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
        post passwords_path, params: { email_address: users(:alice).email_address }
      end
      assert_redirected_to new_session_path
      assert_match(/Password reset instructions sent/i, flash[:notice])

      mail = ActionMailer::Base.deliveries.last
      assert_equal [users(:alice).email_address], mail.to
      assert_match(/Reset your password/i, mail.subject)
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

  test "GET /passwords/:token/edit with a valid token renders the update form" do
    token = users(:alice).password_reset_token
    get edit_password_path(token)
    assert_response :success
    assert_select "form[action=?]", password_path(token)
    assert_select "input[name='password']"
    assert_select "input[name='password_confirmation']"
  end

  test "GET /passwords/:token/edit with an invalid token redirects" do
    get edit_password_path("nope-not-a-real-token")
    assert_redirected_to new_password_path
    assert_match(/invalid or has expired/i, flash[:alert])
  end

  test "PATCH /passwords/:token updates the password with a valid token" do
    token = users(:alice).password_reset_token
    patch password_path(token), params: {
      password: "brand-new-pw",
      password_confirmation: "brand-new-pw"
    }
    assert_redirected_to new_session_path
    assert_match(/updated/i, flash[:notice])

    users(:alice).reload
    assert users(:alice).authenticate("brand-new-pw")
    assert_not users(:alice).authenticate("password123")
  end

  test "PATCH /passwords/:token signs out the account's existing sessions" do
    alice = users(:alice)
    alice.sessions.create!(user_agent: "elsewhere", ip_address: "10.0.0.1")
    patch password_path(alice.password_reset_token), params: {
      password: "brand-new-pw",
      password_confirmation: "brand-new-pw"
    }
    assert_empty alice.reload.sessions
  end

  test "PATCH /passwords/:token with mismatched confirmation redirects back with alert" do
    token = users(:alice).password_reset_token
    patch password_path(token), params: {
      password: "brand-new-pw",
      password_confirmation: "different"
    }
    assert_redirected_to edit_password_path(token)
    assert flash[:alert].present?
    assert users(:alice).reload.authenticate("password123"), "password should be unchanged"
  end

  test "PATCH /passwords/:token with too-short password is rejected" do
    token = users(:alice).password_reset_token
    patch password_path(token), params: {
      password: "short",
      password_confirmation: "short"
    }
    assert_redirected_to edit_password_path(token)
    assert_match(/Password/i, flash[:alert])
    assert users(:alice).reload.authenticate("password123"), "password should be unchanged"
  end

  test "reset token cannot be reused after the password is changed (salt rotates)" do
    token = users(:alice).password_reset_token
    patch password_path(token), params: {
      password: "brand-new-pw",
      password_confirmation: "brand-new-pw"
    }
    assert_redirected_to new_session_path

    # The reset token is scoped to the old password_salt — after a successful reset the token invalidates.
    get edit_password_path(token)
    assert_redirected_to new_password_path
    assert_match(/invalid or has expired/i, flash[:alert])
  end
end
