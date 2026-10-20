require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup { ActionMailer::Base.deliveries.clear }

  def signup_params(overrides = {})
    {
      user: {
        name: "signup_user",
        email_address: "signup@example.com",
        password: "password123",
        password_confirmation: "password123"
      }.merge(overrides)
    }
  end

  test "GET /signup renders the signup form" do
    get signup_path
    assert_response :success
    assert_select "form[action=?]", signup_path
  end

  test "POST /signup (default: mail off) sends user to awaiting activation" do
    assert_difference -> { User.count }, 1 do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        post signup_path, params: signup_params
      end
    end
    user = User.find_by(email_address: "signup@example.com")
    assert_not_nil user
    assert_not user.activated?
    assert_not_nil user.activation_digest
    assert_redirected_to awaiting_activation_path(email: user.email_address)
  end

  test "POST /signup with mail enabled creates a new user and sends activation email" do
    with_mail_enabled do
      assert_difference -> { User.count }, 1 do
        assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
          post signup_path, params: signup_params
        end
      end
      assert_redirected_to root_url
      user = User.find_by(email_address: "signup@example.com")
      assert_not_nil user
      assert_not user.activated?
      assert_not_nil user.activation_digest
      assert_match(/activate/i, flash[:info].to_s)
    end
  end


  test "POST /signup re-renders form on invalid params" do
    assert_no_difference -> { User.count } do
      post signup_path, params: signup_params(name: "")
    end
    assert_response :success
    assert_select "form[action=?]", signup_path
  end

  test "POST /signup rejects duplicate email" do
    assert_no_difference -> { User.count } do
      post signup_path, params: signup_params(email_address: users(:alice).email_address)
    end
    assert_response :success
  end

  test "POST /signup rejects short password" do
    assert_no_difference -> { User.count } do
      post signup_path, params: signup_params(password: "short", password_confirmation: "short")
    end
    assert_response :success
  end
end
