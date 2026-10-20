class JwtsController < ApplicationController
  
  skip_before_action :verify_authenticity_token
  allow_unauthenticated_access only: [ :create, :index ]

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
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
        iss: "rails_jwt_api",
        aud: "rails_jwt_client",
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
      token = request.headers["Authorization"].split(" ").last
      decoded = JWT.decode(token, Rails.application.credentials.jwt_secret, 'HS256')
      user = decoded.first["data"].with_indifferent_access
      if user
        render json: { user: user, credentials: get_credentials_from_cognito(user['id']) }, status: :ok
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
