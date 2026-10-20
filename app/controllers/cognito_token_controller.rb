class CognitoTokenController < ApplicationController

  skip_before_action :verify_authenticity_token

  # get a cognito token linked to the currently logged in user
  def get_credentials
    respond_to do |format|
      format.json do
        # Answer plainly when this instance has no Cognito. Raising here gave a
        # 500 and an HTML error page, which the client could not parse and
        # reported only as a console error.
        unless cognito_configured?
          render json: { error: "S3 is not configured on this server" }, status: :service_unavailable
          next
        end
        render json: get_credentials_from_cognito(current_user.id)
      end
    end
  end
end
