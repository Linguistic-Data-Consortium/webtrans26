require "test_helper"

# POST /kits/graph is what the waveform's Graph button calls: rebuild this kit's
# annotation-graph projection and hand the rows back for display.
class KitsGraphControllerTest < ActionDispatch::IntegrationTest
  setup do
    Annotation.where(id: 0).first_or_create
    @alice = users(:alice)
    @bob = users(:bob)
    @admin = users(:admin)
    @task = tasks(:alpha_task_one)
    @class_def = ClassDef.where(name: "ArcTranscription").first_or_create!
    # graph_payload goes through to_hash, which reads class_def via the kit
    # type's node class.
    root = NodeClass.where(name: "ArcTranscription:Root").first_or_create!(class_def: @class_def)
    @kit_type = KitType.create!(name: "graph-ctl-#{SecureRandom.hex(3)}", node_class: root)
    @tree = Tree.create!(uid: "graph-ctl-#{SecureRandom.hex(3)}", class_def: @class_def, version: 2)
    @kit = Kit.create!(
      task_id: @task.id, kit_type_id: @kit_type.id, tree_id: @tree.id,
      user_id: @alice.id, state: "assigned", uid: "graph-ctl-kit-#{SecureRandom.hex(3)}"
    )
    annotate("add", value: "10:NListItem,11:N")
    annotate("change", iid: 11, docid: "a.wav", begr: 1.25)
    annotate("add", value: "12:NListItem,13:N")
    annotate("change", iid: 13, docid: "a.wav", begr: 3.5)
    annotate("add", value: "14:SegmentListItem,15:Arc,16:Text,17:Speaker")
    annotate("change", iid: 15, begi: 10, endi: 12)
    annotate("change", iid: 16, value: "a line")
    annotate("change", iid: 17, value: "alice")
  end

  def annotate(message, **attributes)
    Annotation.create!(
      { tree_id: @tree.id, task_id: @task.id, user_id: @alice.id, message: message, last_iid: "0" }
        .merge(attributes)
    )
  end

  def build(uid: @kit.uid)
    post kits_graph_url, params: { uid: uid }, as: :json
    JSON.parse(@response.body)
  end

  test "the kit's own annotator can build the graph and gets the rows back" do
    sign_in_as @alice
    body = build
    assert_response :success

    assert_equal 2, body["nodes"].length
    assert_equal [ 10, 12 ], body["nodes"].map { |n| n["iid"] }
    assert_equal [ 1.25, 3.5 ], body["nodes"].map { |n| n["time"] }

    arc = body["arcs"].sole
    assert_equal "SegmentListItem", arc["name"]
    assert_equal 1.25, arc["beg"]
    assert_equal 3.5, arc["end"]

    # What's said about the span comes back separately, keyed to the arc.
    assert_equal [ "Text", "Speaker" ], body["labels"].map { |l| l["name"] }
    assert_equal [ "a line", "alice" ], body["labels"].map { |l| l["value"] }
    assert_equal [ arc["iid"] ] * 2, body["labels"].map { |l| l["arc_iid"] }
  end

  test "the rows are persisted, not just returned" do
    sign_in_as @alice
    assert_difference -> { GraphNode.count }, 2 do
      assert_difference -> { GraphArc.count }, 1 do
        assert_difference -> { GraphLabel.count }, 2 do
          build
        end
      end
    end
  end

  test "a project manager can build it for someone else's kit" do
    sign_in_as @admin # admin ⇒ portal manager ⇒ project manager ⇒ lead_annotator
    build
    assert_response :success
    assert_equal 1, GraphArc.by_tree(@tree.id).count
  end

  test "another annotator cannot" do
    sign_in_as @bob
    assert_no_difference -> { GraphNode.count } do
      assert_equal "permission denied", build["error"]
    end
  end

  test "an unknown kit is reported rather than raising" do
    sign_in_as @alice
    assert_equal "no such kit", build(uid: "nope")["error"]
  end

  test "a kit that has never been opened is reported" do
    sign_in_as @alice
    fresh = Kit.create!(task_id: @task.id, kit_type_id: @task.kit_type_id,
                        user_id: @alice.id, state: "assigned",
                        uid: "graph-none-#{SecureRandom.hex(3)}")
    assert_match(/never been opened/, build(uid: fresh.uid)["error"])
  end

  # ── the payload route ────────────────────────────────────────────────────

  test "graph_payload returns the client payload built from the tables" do
    sign_in_as @alice
    build # take a snapshot first — the payload route only reads

    get "/kits/graph_payload", params: { uid: @kit.uid }, as: :json
    assert_response :success
    body = JSON.parse(@response.body)

    assert_equal [ 10, 11, 12, 13, 14, 15, 16, 17 ], body["nodes"].map { |n| n["iid"] }.sort
    text = body["nodes"].find { |n| n["name"] == "Text" }
    assert_equal 15, text["arc_node_iid"], "the graph payload names the arc a label belongs to"
    value = body["node_values"].find { |v| v["id"] == text["annotation_id"] }
    assert_equal "a line", value["value"]
  end

  test "graph_payload says so when no graph has been built yet" do
    sign_in_as @alice
    get "/kits/graph_payload", params: { uid: @kit.uid }, as: :json
    assert_match(/no graph for that kit yet/, JSON.parse(@response.body)["error"])
  end

  test "graph_payload refuses another annotator" do
    sign_in_as @alice
    build
    delete session_url
    sign_in_as @bob

    get "/kits/graph_payload", params: { uid: @kit.uid }, as: :json
    assert_equal "permission denied", JSON.parse(@response.body)["error"]
  end

  # ── the load-time switch ─────────────────────────────────────────────────

  # The graph shape is how a kit loads now; ?payload= picks another route.
  test "kits#get serves the graph-derived tree by default" do
    sign_in_as @alice
    @kit.update!(user_id: @alice.id)
    @task_user = task_users(:alice_admin_alpha_task_one)
    @task_user.update!(kit_oid: @kit.uid, state: "has_kit")

    get "/kits/get", params: { uid: @kit.uid, task_user_id: @task_user.id, mode: "two" }, as: :json
    assert_response :success
    body = JSON.parse(@response.body)

    assert_equal "graph_memory", body["payload_source"]
    text = body["nodes"].find { |n| n["name"] == "Text" }
    assert_equal 15, text["arc_node_iid"], "these nodes came through the graph shape"
  end

  # It builds the graph in memory, so there's no snapshot to be stale — and
  # nothing is written by loading a kit.
  test "loading a kit writes nothing and needs no snapshot" do
    sign_in_as @alice
    @kit.update!(user_id: @alice.id)
    @task_user = task_users(:alice_admin_alpha_task_one)
    @task_user.update!(kit_oid: @kit.uid, state: "has_kit")
    assert_equal 0, GraphArc.by_tree(@tree.id).count, "nothing stored for this tree yet"

    assert_no_difference -> { GraphNode.count + GraphArc.count + GraphLabel.count } do
      get "/kits/get", params: { uid: @kit.uid, task_user_id: @task_user.id, mode: "two" }, as: :json
    end
    body = JSON.parse(@response.body)
    assert_equal "graph_memory", body["payload_source"]
    assert_equal 8, body["nodes"].length, "the tree is there even with no stored rows"
  end

  # The stored path is kept as the sanity check, reachable on its own.
  test "payload=graph_stored reads what a snapshot stored" do
    sign_in_as @alice
    @kit.update!(user_id: @alice.id)
    @task_user = task_users(:alice_admin_alpha_task_one)
    @task_user.update!(kit_oid: @kit.uid, state: "has_kit")

    get "/kits/get", params: { uid: @kit.uid, task_user_id: @task_user.id, mode: "two", payload: "graph_stored" }, as: :json
    assert_empty JSON.parse(@response.body)["nodes"], "nothing stored yet, so nothing to serve"

    @kit.graph_snapshot
    get "/kits/get", params: { uid: @kit.uid, task_user_id: @task_user.id, mode: "two", payload: "graph_stored" }, as: :json
    body = JSON.parse(@response.body)
    assert_equal "graph", body["payload_source"]
    assert_equal 8, body["nodes"].length
  end

  test "?payload=log still loads the tree from the annotation log" do
    sign_in_as @alice
    @kit.update!(user_id: @alice.id)
    @task_user = task_users(:alice_admin_alpha_task_one)
    @task_user.update!(kit_oid: @kit.uid, state: "has_kit")

    get "/kits/get", params: { uid: @kit.uid, task_user_id: @task_user.id, mode: "two", payload: "log" }, as: :json
    body = JSON.parse(@response.body)
    assert_equal "log", body["payload_source"]
    assert_nil body["nodes"].first["arc_node_iid"]
  end

  test "a signed-out visitor is turned away" do
    post kits_graph_url, params: { uid: @kit.uid }, as: :json
    assert_redirected_to new_session_path
    assert_equal 0, GraphNode.count
  end
end
