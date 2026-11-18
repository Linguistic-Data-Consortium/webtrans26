require "test_helper"

# POST /s3_session and everything that hangs off the same gate — the parallel
# path to POST /token described in aws/s3_project_prefixes.md. STS is stubbed
# (with_s3_sessions); what is checked is what the app asks AWS for and what it
# tells the browser.
class S3SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    @bob = users(:bob)
    @charlie = users(:charlie)
    @alpha = projects(:alpha)
  end

  # ── the gate ───────────────────────────────────────────────────────────────

  # Rendered rather than asserted on the helper: a meta tag is only as good as
  # the layout that emits it.
  test "with nothing configured the page says it is off, and the old tag is unchanged" do
    get new_session_url
    assert_select "meta[name=?][content=?]", "s3-sessions-available", "false"
    assert_select "meta[name=?][content=?]", "s3-available", "false"
  end

  test "configured, the page says it is on — and the Cognito tag still says off" do
    with_s3_sessions do
      get new_session_url
      assert_select "meta[name=?][content=?]", "s3-sessions-available", "true"
      assert_select "meta[name=?][content=?]", "s3-available", "false"
    end
  end

  test "off, POST /s3_session answers with a parseable error, not a 500" do
    sign_in_as @alice
    post "/s3_session", as: :json

    assert_response :service_unavailable
    assert_equal "Per-project S3 is not configured on this server", response.parsed_body["error"]
  end

  test "it wants a region as well as a bucket and a role" do
    with_s3_sessions do
      region = ENV.delete("AWS_REGION")
      saved = Aws.config.delete(:region)
      begin
        sign_in_as @alice
        post "/s3_session", as: :json
        assert_response :service_unavailable
      ensure
        ENV["AWS_REGION"] = region
        Aws.config[:region] = saved if saved
      end
    end
  end

  # ── the session ────────────────────────────────────────────────────────────

  test "a member gets credentials, the bucket and an expiry — and names none of it" do
    asked = nil
    stub = ->(ctx) { asked = ctx.params; S3SessionToggleHelpers.stub_credentials }
    with_s3_sessions(assume_role: stub) do
      sign_in_as @bob
      # Anything the browser sends is ignored: the role, bucket and prefix all
      # come from config and the database.
      post "/s3_session", params: { bucket: "elsewhere", role_arn: "arn:aws:iam::1:role/x", project_id: 999 }, as: :json

      assert_response :success
      body = response.parsed_body
      assert_equal({ "access_key_id" => "ASIATEST", "secret_access_key" => "secret", "session_token" => "token" },
                   body["credentials"])
      assert_equal "test-project-data", body["bucket"]
      assert_equal "us-east-1", body["region"]
      assert_equal "2030-01-01T00:00:00Z", body["expires_at"]

      assert_equal S3SessionToggleHelpers::S3_TEST_ROLE, asked[:role_arn]
      assert_equal "u#{@bob.id}", asked[:role_session_name]
      assert_equal S3SessionsController::DURATION, asked[:duration_seconds]
      policy = JSON.parse(asked[:policy])
      assert_equal [ "arn:aws:s3:::test-project-data/#{@alpha.id}/*" ],
                   policy["Statement"].find { |s| s["Sid"] == "Read" }["Resource"]
      assert_nil policy["Statement"].find { |s| s["Sid"] == "Write" }
    end
  end

  test "membership of the upload task puts a write statement in the session" do
    @alpha.update!(s3_upload_task: tasks(:alpha_task_one))
    asked = nil
    with_s3_sessions(assume_role: ->(ctx) { asked = ctx.params; S3SessionToggleHelpers.stub_credentials }) do
      sign_in_as @bob
      post "/s3_session", as: :json

      assert_response :success
      write = JSON.parse(asked[:policy])["Statement"].find { |s| s["Sid"] == "Write" }
      assert_equal [ "arn:aws:s3:::test-project-data/#{@alpha.id}/*" ], write["Resource"]
    end
  end

  test "no projects is a 403, not a credential" do
    called = false
    with_s3_sessions(assume_role: ->(_) { called = true; S3SessionToggleHelpers.stub_credentials }) do
      sign_in_as @charlie
      post "/s3_session", as: :json

      assert_response :forbidden
      assert_equal "You are not a member of any project", response.parsed_body["error"]
      assert_not called, "STS was asked anyway"
    end
  end

  test "an STS failure is reported, not raised" do
    with_s3_sessions(assume_role: "AccessDenied") do
      sign_in_as @bob
      post "/s3_session", as: :json

      assert_response :bad_gateway
      assert_equal "Could not get S3 credentials", response.parsed_body["error"]
    end
  end

  test "signed out, there is no session" do
    with_s3_sessions do
      post "/s3_session", as: :json
      assert_response :redirect
    end
  end

  # ── designating the upload task ────────────────────────────────────────────

  test "the owner sets the upload task, and the project says which it is" do
    task = tasks(:alpha_task_one)
    sign_in_as @alice
    patch "/projects/#{@alpha.id}", params: { s3_upload_task_id: task.id }, as: :json

    assert_equal task.id, @alpha.reload.s3_upload_task_id
    get "/projects/#{@alpha.id}", as: :json
    body = response.parsed_body
    assert_equal task.id, body["s3_upload_task_id"]
    assert_equal "yes", body["tasks"].find { |t| t["id"] == task.id }["upload"]
  end

  test "a member who isn't the owner can't set it" do
    sign_in_as @bob
    patch "/projects/#{@alpha.id}", params: { s3_upload_task_id: tasks(:alpha_task_one).id }, as: :json

    assert_nil @alpha.reload.s3_upload_task_id
  end

  test "a task from another project is refused" do
    sign_in_as @alice
    patch "/projects/#{@alpha.id}", params: { s3_upload_task_id: tasks(:beta_task_one).id }, as: :json

    assert_nil @alpha.reload.s3_upload_task_id
    assert_match(/must be a task in this project/, response.parsed_body["error"].join)
  end

  # ── the work page ──────────────────────────────────────────────────────────

  def s3_kit(task: tasks(:alpha_task_one), holder: @bob)
    Kit.create!(task_id: task.id, kit_type_id: task.kit_type_id, state: "assigned", user_id: holder.id,
                uid: "s3-kit-#{SecureRandom.hex(3)}", source_uid: "s3://foo/bar/take1.wav",
                source: { uid: "s3://foo/bar/take1.wav" })
  end

  def read_only(kit)
    get "/workflows/#{workflows(:orderly).id}/read_only/#{kit.uid}"
  end

  def work_data
    json = response.body[/window\.ldc_work_work = (\{.*?\});$/, 1]
    assert json, "the page carries no ldc_work_work"
    JSON.parse(json)
  end

  test "off, the work page carries no project context and the manifest is as before" do
    kit = s3_kit
    sign_in_as @bob
    read_only kit

    assert_response :success
    data = work_data
    assert_not data.key?("s3_project")
    assert_equal({ "s3://foo/bar/take1.wav" => "s3://foo/bar/take1.wav" }, data["manifest"]["urls"])
  end

  test "on, the work page names the bucket and the kit's project, and leaves the source alone" do
    kit = s3_kit
    with_s3_sessions do
      sign_in_as @bob
      read_only kit

      assert_response :success
      data = work_data
      assert_equal({ "bucket" => "test-project-data", "project_id" => @alpha.id }, data["s3_project"])
      # Nothing is rewritten on the server: the client resolves it.
      assert_equal({ "s3://foo/bar/take1.wav" => "s3://foo/bar/take1.wav" }, data["manifest"]["urls"])
    end
  end

  test "on, a holder who isn't in the kit's project is told so rather than shown a page that 403s" do
    kit = s3_kit
    project_users(:bob_on_alpha).destroy!
    with_s3_sessions do
      sign_in_as @bob
      read_only kit

      assert_redirected_to root_path
      assert_match(/not a member of this kit's project/, flash[:error])
    end
  end

  test "off, the same holder still sees the page" do
    kit = s3_kit
    project_users(:bob_on_alpha).destroy!
    sign_in_as @bob
    read_only kit

    assert_response :success
  end

  test "on, a kit whose task has no project is refused with a reason" do
    kit = s3_kit
    tasks(:alpha_task_one).update_column(:project_id, nil)
    with_s3_sessions do
      sign_in_as @bob
      read_only kit

      assert_redirected_to root_path
      assert_match(/belongs to no project/, flash[:error])
    end
  end

  test "on, a kit with an http source is not affected" do
    kit = s3_kit
    kit.update!(source_uid: "https://example.org/a.wav", source: { uid: "https://example.org/a.wav" })
    project_users(:bob_on_alpha).destroy!
    with_s3_sessions do
      sign_in_as @bob
      read_only kit

      assert_response :success
    end
  end
end
