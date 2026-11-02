class JwtsController < ApplicationController
  
  skip_before_action :verify_authenticity_token
  allow_unauthenticated_access only: [ :create, :index ]
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { render json: { error: "Try again later." }, status: :too_many_requests }

  ISSUER = "rails_jwt_api"
  AUDIENCE = "rails_jwt_client"

  def create
    # The same answer for an inactive account as for a wrong password: sign-in
    # refuses inactive accounts, and so must this.
    user = User.authenticate_by(params.permit(:email_address, :password))
    if user&.activated?
      encoded_token = encode(user)
      render json: { token: encoded_token }, status: :ok
    else
      render json: { error: "Invalid email or password" }, status: :unauthorized
    end
  end

  # https://dev.to/ruwhan/part-1-rails-8-authentication-but-with-jwt-2if6
  def encode(payload)
    now = Time.now.to_i
    JWT.encode(
      { 
        data: { 
          id: payload.id, 
          email_address: payload.email_address 
        }, 
        exp: now + 3.minutes.to_i,
        iat: now,
        iss: ISSUER,
        aud: AUDIENCE,
        sub: "User",
        jti: SecureRandom.uuid,
        nbf: now + 1.second.to_i,
      }, 
      Rails.application.credentials.jwt_secret, 
      "HS256", 
      { 
        typ: "JWT",
        alg: "HS256"
      }) 
  end

  def index
    begin
      token = request.headers["Authorization"].to_s.split(" ").last
      decoded = JWT.decode(token, Rails.application.credentials.jwt_secret, true,
        algorithm: "HS256", iss: ISSUER, verify_iss: true, aud: AUDIENCE, verify_aud: true)
      # Looked up again rather than trusted from the payload, so an account
      # deactivated after the token was issued gets nothing.
      user = User.find_by(id: decoded.first.dig("data", "id"))
      if user&.activated?
        render json: { user: { id: user.id, email_address: user.email_address }, credentials: get_credentials_from_cognito(user.id) }, status: :ok
      else
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    rescue JWT::ExpiredSignature
      render json: { error: "Token has expired" }, status: :unauthorized
    rescue JWT::DecodeError => e
      logger.info e.to_s
      render json: { error: "segments?" }, status: :unauthorized
    end
  end

end
