require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  test "a user can sign in with valid credentials" do
    visit new_session_url
    fill_in "email_address", with: users(:alice).email_address
    fill_in "password", with: "password123"
    click_on "Sign in"

    assert_current_path(/\/users\/\d+/)
    assert_equal 1, users(:alice).sessions.count
  end

  test "a user sees an error message with wrong password" do
    visit new_session_url
    fill_in "email_address", with: users(:alice).email_address
    fill_in "password", with: "wrong-password"
    click_on "Sign in"

    assert_current_path new_session_path
    assert_text "Try another email address or password"
  end

  test "an unactivated user is blocked at sign-in" do
    visit new_session_url
    fill_in "email_address", with: users(:unactivated).email_address
    fill_in "password", with: "password123"
    click_on "Sign in"

    assert_current_path new_session_path
    assert_text(/hasn.?t been activated/i)
  end

  test "a signed-in user can sign out" do
    visit new_session_url
    fill_in "email_address", with: users(:alice).email_address
    fill_in "password", with: "password123"
    click_on "Sign in"
    assert_current_path(/\/users\/\d+/)

    # #newsignout is rendered hidden by the layout — the visible sticky header
    # was retired in favour of the `s` keybinding. Submit the form directly.
    page.execute_script("document.querySelector('#newsignout form').submit()")

    assert_current_path new_session_path
    assert_equal 0, users(:alice).sessions.count
  end

  test "the sign-in page links to the signup form" do
    visit new_session_url
    click_on "Create account"
    assert_current_path new_user_path
    assert_text "Sign up"
  end
end
