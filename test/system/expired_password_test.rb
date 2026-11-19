require "application_system_test_case"

# A password past its age is replaced before anything else, in a real browser,
# under the CSP the system suite enforces.
class ExpiredPasswordTest < ApplicationSystemTestCase
  test "an expired password is replaced on sign-in before the dashboard opens" do
    alice = users(:alice)
    alice.update_columns(password_changed_at: (User.password_max_age + 1.day).ago)

    visit new_session_url
    fill_in "email_address", with: alice.email_address
    fill_in "password", with: "password123"
    click_on "Sign in"

    assert_current_path edit_account_password_path
    assert_text "Choose a new password"

    # One the server refuses is sent back with the reason. (Anything under 16
    # characters the browser won't submit at all, from the field's minlength.)
    fill_in "Current password", with: "password123"
    fill_in "New password", with: "Glacier#P@ssw0rd-Mild"
    fill_in "Confirm new password", with: "Glacier#P@ssw0rd-Mild"
    click_on "Set password"
    assert_current_path edit_account_password_path
    assert_text "must not contain a common word"

    fill_in "Current password", with: "password123"
    fill_in "New password", with: GOOD_PASSWORD
    fill_in "Confirm new password", with: GOOD_PASSWORD
    click_on "Set password"

    assert_text "Your password has been changed"
    assert_current_path(%r{\A/users/\d+\z}, wait: 10)
    assert_not alice.reload.password_expired?
  end
end
