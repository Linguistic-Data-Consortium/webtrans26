require "application_system_test_case"

# Setting up two-step sign-in and then using it, in a real browser under the
# CSP the system suite enforces.
class MfaSystemTest < ApplicationSystemTestCase
  test "a user sets up an authenticator, saves recovery codes, and signs in with a code" do
    with_mfa_enabled do
      alice = users(:alice)
      sign_in_with_password(alice)
      assert_current_path account_mfa_path
      assert_selector "#mfa-qr img"
      assert_operator evaluate_script("document.querySelector('#mfa-qr img').naturalWidth"), :>, 0, "the QR image decodes"

      # What an authenticator app would do with the key shown.
      secret = find("#mfa-secret").text.delete(" ")
      fill_in "Code from the app", with: ROTP::TOTP.new(secret).now
      click_on "Turn on two-step sign-in"
      assert_text "Save your recovery codes"
      assert_selector "#recovery-codes li", count: User::Mfa::RECOVERY_CODE_COUNT
      click_on "I've saved them — continue"
      assert_current_path(%r{\A/users/\d+\z}, wait: 10)

      page.driver.browser.manage.delete_all_cookies
      sign_in_with_password(alice)
      assert_current_path new_session_mfa_path
      fill_in "Code", with: ROTP::TOTP.new(secret).at(Time.now + 30) # a step not yet used
      click_on "Verify"
      assert_current_path(%r{\A/users/\d+\z}, wait: 10)
    end
  end

  def sign_in_with_password(user)
    visit new_session_url
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password123"
    click_on "Sign in"
  end
end
