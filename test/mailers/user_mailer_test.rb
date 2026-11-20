require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "password_reset mail has the right recipient, subject, and a link with the reset token" do
    user = users(:alice)
    user.reset_token = User.new_token
    mail = UserMailer.password_reset(user)

    assert_equal [user.email_address], mail.to
    assert_equal "Password reset", mail.subject
    assert_match user.reset_token, mail.body.encoded
    assert_match CGI.escape(user.email_address), mail.body.encoded
  end

  test "invite mail has the right recipient, subject, and a link to /invites/:token/edit" do
    user = User.new(email_address: "newinvite_#{SecureRandom.hex(3)}@example.com", password: User.new_token)
    user.save(validate: false)
    user.create_invite_digest(users(:admin).id)

    mail = UserMailer.invite(user)

    assert_equal [user.email_address], mail.to
    assert_equal "LDC Portal Invitation", mail.subject
    assert_match user.invite_token, mail.body.encoded
    assert_match "/invites/", mail.body.encoded
    assert_match "/edit", mail.body.encoded
    assert_match CGI.escape(user.email_address), mail.body.encoded
  end

  test "invitation mail carries the link and who sent it" do
    mail = UserMailer.invitation(users(:alice), "https://app.test/access/1/tok", users(:pat))
    assert_equal [ users(:alice).email_address ], mail.to
    assert_match "https://app.test/access/1/tok", mail.body.encoded
    assert_match users(:pat).name, mail.body.encoded
  end
end

