class UserMailer < ApplicationMailer

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.user_mailer.account_activation.subject
  #
  def account_activation(user)
    @user = user
    mail to: user.email_address, subject: 'Account activation'
  end

  # Someone used this address to sign up, and it already has an account. The
  # signup page answered as if it were new, so as not to tell them, and the
  # owner hears about it here instead.
  def signup_attempt(user)
    @user = user
    mail to: user.email_address, subject: 'Sign-up attempt with your address'
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
