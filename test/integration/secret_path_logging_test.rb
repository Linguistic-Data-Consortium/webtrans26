require "test_helper"

# The "Started GET ..." line is written from the request path, which
# filter_parameters doesn't touch. Links whose secret is a path segment have
# that segment masked there (config/initializers/filter_secret_paths.rb).
class SecretPathLoggingTest < ActionDispatch::IntegrationTest
  def logged(&block)
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    # The request line goes to Rails.logger, the controller's lines to its own.
    originals = [ Rails.logger, ActionController::Base.logger ]
    Rails.logger = ActionController::Base.logger = logger
    yield
    io.string
  ensure
    Rails.logger, ActionController::Base.logger = originals
  end

  test "an access link's token is masked in the request log" do
    user = users(:unactivated)
    token = user.create_access_digest(users(:admin).id)
    log = logged { get access_link_path(user.id, token) }
    assert_includes log, %(Started GET "/access/#{user.id}/[FILTERED]")
    assert_not_includes log, token
  end

  test "a reset link's token is masked, and the redirect after it carries none" do
    token = users(:alice).password_reset_token
    log = logged { get edit_password_path(token) }
    assert_includes log, %(Started GET "/passwords/[FILTERED]/edit")
    assert_includes log, "Redirected to http://www.example.com/passwords/reset"
    assert_not_includes log, token
  end
end
