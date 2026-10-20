require "test_helper"

# The SAD/ASR endpoint and its bucket reach the client through meta tags, the
# same channel getp.js uses for the CSRF token. The client's fallbacks are what
# the values used to be hardcoded as, which means a layout that silently stopped
# rendering these tags would look fine on an LDC instance and point everywhere
# else at the wrong host. So assert the tags are actually there.
class ServiceConfigMetaTest < ActionDispatch::IntegrationTest
  test "the layout renders the configured endpoint and bucket" do
    get new_session_url

    assert_select "meta[name=?][content=?]", "hlt-endpoint",
                  Rails.application.config.x.hlt_endpoint
    assert_select "meta[name=?][content=?]", "promise-bucket",
                  Rails.application.config.x.promise_bucket
  end

  # This app is the public release: an unconfigured instance must not fall back
  # to LDC's own service. Both are empty until HLT_ENDPOINT / PROMISE_BUCKET are
  # set, which also means no default here names a host or bucket that would
  # receive a stranger's audio.
  test "nothing is configured by default, and no default names LDC" do
    assert_equal "", Rails.application.config.x.hlt_endpoint
    assert_equal "", Rails.application.config.x.promise_bucket
  end
end
