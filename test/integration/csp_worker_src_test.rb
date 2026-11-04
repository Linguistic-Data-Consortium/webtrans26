require "test_helper"

# A Worker has no CSP default of its own: without worker-src it falls back to
# default-src, which is 'self' alone. That blocks the blob: workers bundlers and
# onnxruntime-web create, and the only sign is a violation in a console no
# annotator reads — so assert the directive is actually sent, not just that it
# is written in the initializer.
#
# In-browser speech recognition runs in a Worker, and the engine loads its
# backend as a blob: URL inside that worker -- so worker-src needs 'self' and
# blob:, and script-src needs blob: as well. Without the second the worker
# silently never starts, and only on a deployed instance.
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

  # Allowing the Worker to be created is only half of it: onnxruntime-web then
  # loads its own glue from a blob: URL inside that Worker, and a script load
  # falls back to script-src. Deploying without this gets
  #   Loading the script 'blob:https://…' violates … "script-src 'self' …"
  # and the engine never starts, which is how it was found.
  test "blob: scripts are allowed, which the recognition engine loads inside its worker" do
    get new_session_url

    csp = response.headers["Content-Security-Policy"]
    assert_match(/script-src [^;]*\bblob:/, csp)
  end
end
