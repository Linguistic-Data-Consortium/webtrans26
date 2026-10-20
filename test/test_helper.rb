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

class ActionDispatch::IntegrationTest
  include SignInHelpers
  include MailToggleHelpers
end
