require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset mail has correct recipient, subject, and a reset link with the token in its fragment" do
    user = users(:alice)
    mail = PasswordsMailer.reset(user)

    assert_equal [user.email_address], mail.to
    assert_equal "Reset your password", mail.subject
    # Each call to password_reset_token generates a fresh token, so we can't assert equality.
    # The token rides after the #, which a browser never sends, so no log records it.
    assert_match %r{/passwords/reset#\S+}, mail.body.encoded
    assert_no_match %r{/passwords/[^#\s]+/edit}, mail.body.encoded
  end
end
