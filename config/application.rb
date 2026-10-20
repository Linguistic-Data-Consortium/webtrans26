require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Webtrans26
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.active_record.default_column_serializer = YAML

    # Enable Rack::Attack middleware for rate limiting
    config.middleware.use Rack::Attack

    # Outbound email is opt-in: by default this repo has no SMTP configured,
    # so the account-activation email path would crash. When disabled, signups
    # land on a "please wait for activation" page instead.
    config.x.mail_enabled = ENV["MAIL_ENABLED"] == "true"

    # Set by bin/repl and the transcription REPL/auto harnesses. When on, the
    # front end suppresses the training guide popup so the scripted runs aren't
    # blocked by it (see app/javascript/lib/transcription_guide.svelte).
    config.x.transcription_repl = ENV["TRANSCRIPTION_REPL"] == "1"
    # The speech-activity-detection / ASR promise service, and the S3 bucket it
    # exchanges work through. Both used to be string literals repeated across
    # the client, which meant a deployment outside LDC had no way to point them
    # anywhere else. The client reads these from meta tags in the layout; see
    # app/javascript/lib/ldcjs/service_config.js.
    #
    # Unlike wta, these default to empty rather than to LDC's own service:
    # this app is the public release, and an unconfigured instance must not
    # send a stranger's audio to a host they have never heard of. Speech
    # activity detection and ASR are simply unavailable until both are set.
    config.x.hlt_endpoint  = ENV.fetch("HLT_ENDPOINT", "")
    config.x.promise_bucket = ENV.fetch("PROMISE_BUCKET", "")

    # Whether the browser can reach S3. Set per-request rather than here,
    # because it depends on credentials and on AWS_REGION — see
    # ApplicationController#cognito_configured? and the s3-available meta tag.

  end
end
