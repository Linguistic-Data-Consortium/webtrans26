require "test_helper"

class JwtsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Test env credentials may not include a jwt_secret. Stub a stable one for these tests.
    @stub_secret = "test-jwt-secret-#{SecureRandom.hex(8)}"
    @creds = Rails.application.credentials
    @creds.singleton_class.send(:define_method, :jwt_secret) { @_test_jwt_secret }
    @creds.instance_variable_set(:@_test_jwt_secret, @stub_secret)
  end

  teardown do
    @creds.singleton_class.send(:remove_method, :jwt_secret)
  end

  test "POST /jwts with valid credentials returns a JWT for the user" do
    post jwts_url, params: { email_address: users(:alice).email_address, password: "password123" }, as: :json
    assert_response :success
    body = JSON.parse(@response.body)
    assert body["token"].present?

    # The controller sets `nbf` to `now + 1.second`, so we'd hit ImmatureSignature if we
    # decoded immediately. Disable the nbf check for the test.
    decoded = JWT.decode(body["token"], @stub_secret, true, { algorithm: "HS256", verify_not_before: false })
    payload = decoded.first
    assert_equal users(:alice).id, payload["data"]["id"]
    assert_equal users(:alice).email_address, payload["data"]["email_address"]
  end

  test "POST /jwts with bad credentials returns 401" do
    post jwts_url, params: { email_address: users(:alice).email_address, password: "wrong" }, as: :json
    assert_response :unauthorized
    body = JSON.parse(@response.body)
    assert_equal "Invalid email or password", body["error"]
  end

  test "POST /jwts with unknown email returns 401" do
    post jwts_url, params: { email_address: "ghost@example.com", password: "password123" }, as: :json
    assert_response :unauthorized
  end

  test "GET /jwts with an invalid token returns 401" do
    get jwts_url, headers: { "Authorization" => "Bearer not.a.real.jwt" }, as: :json
    assert_response :unauthorized
    body = JSON.parse(@response.body)
    assert body["error"].present?
  end
end
