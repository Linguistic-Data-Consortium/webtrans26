require "test_helper"

# There is no public signup: accounts come by invitation (AccessLinksController).
class UsersControllerTest < ActionDispatch::IntegrationTest
  test "the signup page and form are gone" do
    get "/signup"
    assert_response :not_found
    post "/signup", params: { user: { name: "x", email_address: "x@example.com", password: GOOD_PASSWORD } }
    assert_response :not_found
  end

  test "nor can an account be created through /users" do
    assert_no_difference -> { User.count } do
      post "/users", params: { user: { name: "x", email_address: "x@example.com",
                                       password: GOOD_PASSWORD, password_confirmation: GOOD_PASSWORD } }
    end
  end

  test "the old activation-link path is gone too" do
    get "/account_activations/whatever/edit", params: { email: users(:alice).email_address }
    assert_response :not_found
  end
end
