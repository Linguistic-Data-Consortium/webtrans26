require "test_helper"

# The signup form used to promise a verification link unconditionally, while
# UsersController#create only sends one when mail is enabled — and mail is off
# by default, so the default deployment's own signup page was wrong about what
# would happen next. The awaiting_activation page it redirects to has always
# said the honest thing; this asserts the form agrees with it.
class SignupEmailWordingTest < ActionDispatch::IntegrationTest
  def with_mail(enabled)
    was = Rails.application.config.x.mail_enabled
    Rails.application.config.x.mail_enabled = enabled
    yield
  ensure
    Rails.application.config.x.mail_enabled = was
  end

  test "with no mail configured — the default — the form promises no link" do
    with_mail(false) do
      get signup_path
      assert_response :success
      assert_includes response.body, "This instance doesn&#39;t send email"
      assert_includes response.body, "wait for one of them to activate it"
      refute_includes response.body, "send a verification link"
    end
  end

  test "with mail enabled the form says a link is coming" do
    with_mail(true) do
      get signup_path
      assert_response :success
      assert_includes response.body, "send a verification link"
      refute_includes response.body, "This instance doesn&#39;t send email"
    end
  end

  test "both versions still promise not to share the address" do
    for_each = [ true, false ]
    for_each.each do |enabled|
      with_mail(enabled) do
        get signup_path
        assert_includes response.body, "never share your email"
      end
    end
  end

  # The form and the page it lands on have to tell the same story, which is the
  # bug: one said "check your email", the other "an administrator has to
  # activate your account".
  #
  # Note the apostrophe: this page's text is literal haml content, so it
  # reaches the browser as a plain `\'`, while the form's notice is a Ruby
  # string rendered through `=` and so arrives escaped as `&#39;`. Same visible
  # character, two different bytes, and asserting the wrong one is how this
  # test first failed.
  test "the mailless form agrees with the page signup actually reaches" do
    with_mail(false) do
      get awaiting_activation_path(email: "someone@example.com")
      assert_response :success
      assert_includes response.body, "isn't configured to send email"
      assert_includes response.body, "activate your account manually"
    end
  end
end
