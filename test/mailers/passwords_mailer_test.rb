require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset mail has correct recipient, subject, and includes an edit-password link" do
    user = users(:alice)
    mail = PasswordsMailer.reset(user)

    assert_equal [user.email_address], mail.to
    assert_equal "Reset your password", mail.subject
    # Each call to password_reset_token generates a fresh token, so we can't assert equality —
    # instead we assert the body contains a well-formed edit-password URL.
    assert_match %r{/passwords/[^\s]+/edit}, mail.body.encoded
  end
end
