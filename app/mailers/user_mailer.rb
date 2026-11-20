class UserMailer < ApplicationMailer

  # An invitation (AccessLinksController): the one-time link that signs the
  # person in and has them choose a password. Only when MAIL_ENABLED and the
  # inviter asked for it; otherwise they pass the link on themselves.
  def invitation(user, url, inviter)
    @user, @url, @inviter = user, url, inviter
    mail to: user.email_address, subject: "Your invitation"
  end

  def invite(user)
    @user = user
    @invite_frontend_url = root_url + "invites/" + @user.invite_token + "/edit?email=" + ERB::Util.url_encode(@user.email_address)
    mail to: user.email_address, subject: "LDC Portal Invitation"
  end

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.user_mailer.password_reset.subject
  #
  def password_reset(user)
    @user = user
    mail to: user.email_address, subject: 'Password reset'
  end

end
