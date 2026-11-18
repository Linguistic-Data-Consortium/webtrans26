ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

Rack::Attack.enabled = false

# Vite tag helpers are stubbed to no-ops by default so most tests can render layouts without
# depending on a built Vite manifest. System tests that need to exercise the real Svelte app
# can toggle this off by setting ViteStub.enabled = false (see test/system/dashboard_test.rb).
module ViteStub
  class << self
    attr_accessor :enabled
  end
  self.enabled = true
end

module ViteRails::TagHelpers
  %i[vite_client_tag vite_javascript_tag vite_typescript_tag vite_stylesheet_tag vite_image_tag].each do |m|
    original = instance_method(m)
    define_method(m) do |*args, **kwargs, &block|
      next "".html_safe if ViteStub.enabled
      original.bind(self).call(*args, **kwargs, &block)
    end
  end

  %i[vite_asset_path vite_asset_url].each do |m|
    original = instance_method(m)
    define_method(m) do |*args, **kwargs, &block|
      next "" if ViteStub.enabled
      original.bind(self).call(*args, **kwargs, &block)
    end
  end
end

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all
  end
end

module SignInHelpers
  def sign_in_as(user, password: "password123")
    post session_url, params: { email_address: user.email_address, password: password }
  end

  def sign_in_via_cookie(user)
    session = user.sessions.create!(user_agent: "Rails Testing", ip_address: "127.0.0.1")
    cookies.signed[:session_id] = session.id
    session
  end
end

# Flips Rails.application.config.x.mail_enabled on for the duration of the
# block. Used by tests that exercise the activation / password-reset paths
# that send email — by default this repo runs with mail disabled.
module MailToggleHelpers
  def with_mail_enabled
    original = Rails.application.config.x.mail_enabled
    Rails.application.config.x.mail_enabled = true
    yield
  ensure
    Rails.application.config.x.mail_enabled = original
  end
end

# Turns the per-project S3 path (POST /s3_session) on for the block: a bucket,
# a role and a region, which is what Authentication#s3_sessions_configured?
# asks for. Nothing reaches AWS — STS is stubbed through Aws.config, and
# `assume_role` may be a Proc to capture what was asked for.
module S3SessionToggleHelpers
  S3_TEST_BUCKET = "test-project-data"
  S3_TEST_ROLE = "arn:aws:iam::000000000000:role/test-project-data"

  def with_s3_sessions(assume_role: nil)
    x = Rails.application.config.x
    saved = [ x.s3_bucket, x.s3_role_arn, ENV["AWS_REGION"], Aws.config[:sts] ]
    x.s3_bucket = S3_TEST_BUCKET
    x.s3_role_arn = S3_TEST_ROLE
    ENV["AWS_REGION"] = "us-east-1"
    Aws.config[:sts] = { stub_responses: { assume_role: assume_role || S3SessionToggleHelpers.stub_credentials } }
    yield
  ensure
    x.s3_bucket, x.s3_role_arn, region, sts = saved
    region.nil? ? ENV.delete("AWS_REGION") : ENV["AWS_REGION"] = region
    sts.nil? ? Aws.config.delete(:sts) : Aws.config[:sts] = sts
  end

  def self.stub_credentials
    { credentials: { access_key_id: "ASIATEST", secret_access_key: "secret", session_token: "token",
                     expiration: Time.utc(2030, 1, 1) } }
  end
end

class ActionDispatch::IntegrationTest
  include SignInHelpers
  include MailToggleHelpers
  include S3SessionToggleHelpers
end
