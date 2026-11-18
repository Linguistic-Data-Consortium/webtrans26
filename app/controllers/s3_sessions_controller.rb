# POST /s3_session — temporary S3 credentials scoped to the caller's projects.
#
# The parallel path to POST /token (CognitoTokenController), described in
# aws/s3_project_prefixes.md. The difference that matters: there the browser
# exchanges a token for credentials, so the credentials carry whatever the
# identity pool's one role allows. Here the server does the exchange, with
# sts:AssumeRole and a session policy built from Active Record
# (S3SessionPolicy), so each user's credentials reach only their own projects'
# prefixes. Nothing in AWS changes when a project or a member is added.
#
# The client names nothing — not the role, the bucket or a prefix. All three
# come from config and the database.
class S3SessionsController < ApplicationController
  # Credentials go to a browser, so they live no longer than the audio they
  # sign. A presigned URL dies with the credentials that signed it, and the
  # audio element streams from one with range requests for as long as the page
  # is open, so 900 s (the STS minimum) would cut playback off a quarter-hour
  # in. One hour matches what the Cognito path hands out and the default
  # maximum session duration of a role.
  DURATION = 3600

  def create
    respond_to do |format|
      format.json do
        unless s3_sessions_configured?
          render json: { error: "Per-project S3 is not configured on this server" }, status: :service_unavailable
          next
        end

        policy = S3SessionPolicy.new(current_user)
        if policy.empty?
          # An empty session policy would deny everything, so issuing one would
          # be safe — but it says nothing, and keeps a useless credential in a
          # browser. Refuse instead.
          render json: { error: "You are not a member of any project" }, status: :forbidden
          next
        end

        creds = assume_role(policy)
        Rails.logger.info(
          "s3_session user=#{current_user.id} read=#{policy.read_ids.join(',')} " \
          "write=#{policy.write_ids.join(',')} expires=#{creds.expiration.iso8601}"
        )
        render json: {
          credentials: {
            access_key_id: creds.access_key_id,
            secret_access_key: creds.secret_access_key,
            session_token: creds.session_token
          },
          region: region,
          bucket: Rails.application.config.x.s3_bucket,
          expires_at: creds.expiration.iso8601
        }
      end
    end
  rescue Aws::STS::Errors::PackedPolicyTooLarge
    # Each project adds an ARN to two statements and a prefix to a third, so a
    # member of very many projects can outgrow the packed limit. Say so rather
    # than 500.
    render json: { error: "Too many projects to fit in one S3 session" }, status: :unprocessable_entity
  rescue Aws::Errors::ServiceError => e
    Rails.logger.error("s3_session user=#{current_user&.id} failed: #{e.class}: #{e.message}")
    render json: { error: "Could not get S3 credentials" }, status: :bad_gateway
  end

  private

  def assume_role(policy)
    sts_client.assume_role(
      role_arn: Rails.application.config.x.s3_role_arn,
      role_session_name: "u#{current_user.id}", # appears in CloudTrail
      policy: policy.to_json,                    # the narrowing
      duration_seconds: DURATION
    ).credentials
  end

  # A seam for tests, which stub it rather than reach AWS.
  def sts_client
    Aws::STS::Client.new(region: region)
  end

  def region
    ENV["AWS_REGION"].presence || Aws.config[:region]
  end
end
