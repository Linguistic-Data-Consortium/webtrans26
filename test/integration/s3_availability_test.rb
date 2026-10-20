require "test_helper"

# The browser reaches S3 only through POST /token, so with no Cognito and no
# region every s3:// source and the whole bucket browser are dead. That used to
# surface as a 500, an unparseable HTML body, and then "cannot read properties
# of undefined" in the console — so the layout now states it and the client
# stays out of the way.
class S3AvailabilityTest < ActionDispatch::IntegrationTest
  include SignInHelpers

  test "the layout states it, and this instance has no cognito so it is false" do
    get new_session_url
    assert_select "meta[name=?][content=?]", "s3-available", "false"
  end

  test "POST /token answers with a parseable error, not a 500" do
    sign_in_as users(:alice)
    post "/token", as: :json

    assert_response :service_unavailable
    assert_equal "S3 is not configured on this server", JSON.parse(response.body)["error"]
  end
end
