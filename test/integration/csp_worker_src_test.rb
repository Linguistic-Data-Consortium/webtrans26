require "test_helper"

# A Worker has no CSP default of its own: without worker-src it falls back to
# default-src, which is 'self' alone. That blocks the blob: workers bundlers and
# onnxruntime-web create, and the only sign is a violation in a console no
# annotator reads — so assert the directive is actually sent, not just that it
# is written in the initializer.
#
# In-browser speech recognition runs in a Worker; see
# app_comparison/ports/local-stt.md.
class CspWorkerSrcTest < ActionDispatch::IntegrationTest
  test "the CSP sends worker-src, allowing same-origin and blob: workers" do
    get new_session_url

    csp = response.headers["Content-Security-Policy"]
    assert csp.present?, "no Content-Security-Policy header"
    assert_includes csp, "worker-src 'self' blob:"
  end

  test "default-src is still restrictive, which is why worker-src is needed" do
    get new_session_url

    assert_includes response.headers["Content-Security-Policy"], "default-src 'self'"
  end
end
