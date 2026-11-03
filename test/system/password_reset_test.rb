require "application_system_test_case"

class PasswordResetTest < ApplicationSystemTestCase
  setup { ActionMailer::Base.deliveries.clear }

  test "with mail disabled (default), the recovery page points at an access link and changes nothing" do
    alice = users(:alice)
    digest = alice.password_digest

    visit new_session_url
    click_on "Username/password recovery"

    assert_current_path new_password_path
    assert_text "sign-in link"
    assert_no_field "Email address"
    alice.reload
    assert alice.activated?
    assert_equal digest, alice.password_digest
  end

  test "with mail enabled, a user can reset their password via the email link" do
    with_mail_enabled do
      user = users(:alice)
      new_password = "fresh-new-pw"

      # Step 1: request the reset from the sign-in page
      visit new_session_url
      click_on "Username/password recovery"

      assert_current_path new_password_path
      fill_in "Email address", with: user.email_address
      click_on "Send reset instructions"

      assert_current_path new_session_path
      assert_text "Password reset instructions sent"

      # Step 2: grab the reset URL out of the delivered email
      mail = ActionMailer::Base.deliveries.last
      assert_not_nil mail
      assert_equal [user.email_address], mail.to

      # The token rides in the fragment, which the browser never sends; the
      # claim page's script posts it.
      link = mail.body.encoded[%r{/passwords/reset#\S+}]
      assert_not_nil link, "email body should include a /passwords/reset#token link"
      edit_path = link

      # Step 3: follow the link and submit a new password
      visit edit_path
      assert_text "Update your password"
      assert_equal "", evaluate_script("window.location.hash"), "the token is gone from the address bar"
      assert_current_path reset_password_path

      fill_in "New password", with: new_password
      fill_in "Confirm password", with: new_password
      click_on "Update password"

      assert_current_path new_session_path
      assert_text "updated"

      # Step 4: user can now sign in with the new password
      fill_in "email_address", with: user.email_address
      fill_in "password", with: new_password
      click_on "Sign in"

      assert_current_path(/\/users\/\d+/)
    end
  end
end
