require "test_helper"

class JwtsControllerTest < ActionDispatch::IntegrationTest
  # `resources :jwts` is commented out as of 2026-11-05 and the controller kept
  # for later, so every test here would die on `jwts_url` being undefined.
  # Skipping on the route's absence rather than hardcoding a skip means these
  # nine come back on their own the moment the route is uncommented — nobody
  # has to remember this file exists.
  ROUTE_LIVE = Rails.application.routes.routes.any? { |r| r.defaults[:controller] == "jwts" }

  setup do
    skip "resources :jwts is commented out in config/routes.rb" unless ROUTE_LIVE

    # Test env credentials may not include a jwt_secret. Stub a stable one for these tests.
    @stub_secret = "test-jwt-secret-#{SecureRandom.hex(8)}"
    @creds = Rails.application.credentials
    @creds.singleton_class.send(:define_method, :jwt_secret) { @_test_jwt_secret }
    @creds.instance_variable_set(:@_test_jwt_secret, @stub_secret)
  end

  teardown do
    next unless ROUTE_LIVE
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

  test "POST /jwts refuses an account that isn't activated, with the bad-password answer" do
    user = users(:unactivated)
    user.update!(password: "password123", password_confirmation: "password123")
    post jwts_url, params: { email_address: user.email_address, password: "password123" }, as: :json
    assert_response :unauthorized
    assert_equal "Invalid email or password", JSON.parse(@response.body)["error"]
  end

  test "GET /jwts without an Authorization header returns 401, not 500" do
    get jwts_url, as: :json
    assert_response :unauthorized
  end

  test "GET /jwts refuses a validly signed token for a deactivated account" do
    alice = users(:alice)
    token = JWT.encode({ data: { id: alice.id }, exp: 1.minute.from_now.to_i,
      iss: JwtsController::ISSUER, aud: JwtsController::AUDIENCE }, @stub_secret, "HS256")
    alice.update_columns(activated: false)
    get jwts_url, headers: { "Authorization" => "Bearer #{token}" }, as: :json
    assert_response :unauthorized
  end

  test "GET /jwts refuses a token signed for another audience" do
    token = JWT.encode({ data: { id: users(:alice).id }, exp: 1.minute.from_now.to_i,
      iss: JwtsController::ISSUER, aud: "someone-else" }, @stub_secret, "HS256")
    get jwts_url, headers: { "Authorization" => "Bearer #{token}" }, as: :json
    assert_response :unauthorized
  end

  test "GET /jwts accepts a valid token for an active account" do
    alice = users(:alice)
    token = JWT.encode({ data: { id: alice.id }, exp: 1.minute.from_now.to_i,
      iss: JwtsController::ISSUER, aud: JwtsController::AUDIENCE }, @stub_secret, "HS256")
    JwtsController.class_eval { alias_method :__real_creds, :get_credentials_from_cognito; define_method(:get_credentials_from_cognito) { |id| { stub: id } } }
    get jwts_url, headers: { "Authorization" => "Bearer #{token}" }, as: :json
    assert_response :success
    assert_equal alice.id, JSON.parse(@response.body).dig("credentials", "stub")
  ensure
    JwtsController.class_eval { alias_method :get_credentials_from_cognito, :__real_creds; remove_method :__real_creds }
  end
end

