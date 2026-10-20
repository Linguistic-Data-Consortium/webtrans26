require "test_helper"

# GET /projects/:project_id/tasks/:id/graph — the task's annotation graph,
# drawn. The HTML mounts the viewer; the JSON is what it reads: every kit in
# the task snapshotted into graph_nodes / graph_arcs / graph_labels and handed
# back as anchors, spans and labels.
class TaskGraphControllerTest < ActionDispatch::IntegrationTest
  setup do
    Annotation.where(id: 0).first_or_create
    @alice = users(:alice) # task admin on alpha_task_one
    @bob   = users(:bob)   # a member of it, not an admin
    @alpha = projects(:alpha)
    @task  = tasks(:alpha_task_one)
    @class_def = ClassDef.where(name: "ArcTranscription").first_or_create!
    root = NodeClass.where(name: "ArcTranscription:Root").first_or_create!(class_def: @class_def)
    @kit_type = KitType.create!(name: "task-graph-#{SecureRandom.hex(3)}", node_class: root)

    @kit = annotated_kit do |tree|
      # Two anchors and a segment between them, plus a section over the same
      # stretch — the two groups the transcript is made of.
      annotate(tree, "add", value: "10:NListItem,11:N")
      annotate(tree, "change", iid: 11, docid: "a.wav", begr: 1.25)
      annotate(tree, "add", value: "12:NListItem,13:N")
      annotate(tree, "change", iid: 13, docid: "a.wav", begr: 3.5)
      annotate(tree, "add", value: "14:SegmentListItem,15:Arc,16:Text,17:Speaker")
      annotate(tree, "change", iid: 15, begi: 10, endi: 12)
      annotate(tree, "change", iid: 16, value: "a line")
      annotate(tree, "change", iid: 17, value: "alice")
      annotate(tree, "add", value: "30:SectionListItem,31:Arc,32:Name")
      annotate(tree, "change", iid: 31, begi: 10, endi: 12)
      annotate(tree, "change", iid: 32, value: "intro")
    end
  end

  def annotated_kit(user: @alice, state: "assigned")
    tree = Tree.create!(uid: "task-graph-#{SecureRandom.hex(4)}", class_def: @class_def, version: 2)
    yield tree if block_given?
    Kit.create!(
      task_id: @task.id, kit_type_id: @kit_type.id, tree_id: tree.id,
      user_id: user.id, state: state, uid: "task-graph-kit-#{SecureRandom.hex(4)}",
      source_uid: "a.wav"
    )
  end

  def annotate(tree, message, **attributes)
    Annotation.create!(
      { tree_id: tree.id, task_id: @task.id, user_id: @alice.id, message: message, last_iid: "0" }
        .merge(attributes)
    )
  end

  def fetch(**params)
    get graph_project_task_url(project_id: @alpha.id, id: @task.id, **params), as: :json
    JSON.parse(@response.body)
  end

  # ── what it draws ─────────────────────────────────────────────────────────

  test "a task admin gets a block per annotated kit, with its rows" do
    sign_in_as @alice
    body = fetch
    assert_response :success

    block = body["kits"].sole
    assert_equal @kit.id, block["kit_id"]
    assert_equal @kit.uid, block["uid"]
    assert_equal "a.wav", block["docid"]
    assert_equal @alice.name, block["user"]
    assert_equal "assigned", block["state"]

    assert_equal [ 10, 12 ], block["nodes"].map { |n| n["iid"] }
    assert_equal [ 1.25, 3.5 ], block["nodes"].map { |n| n["time"] }
  end

  test "spans come back with their anchors' times filled in" do
    sign_in_as @alice
    arcs = fetch["kits"].sole["arcs"]

    segment = arcs.find { |a| a["name"] == "SegmentListItem" }
    assert_equal 1.25, segment["beg"]
    assert_equal 3.5, segment["end"]
    assert_equal 10, segment["beg_iid"]
    assert_equal 12, segment["end_iid"]
    # The arc's own identity and the group's Arc child are different nodes, and
    # the drawing shows both — so both have to survive the trip.
    assert_equal 14, segment["iid"]
    assert_equal 15, segment["arc_node_iid"]
  end

  test "labels come back keyed to the arc's iid, not its arc node" do
    sign_in_as @alice
    body = fetch
    labels = body["kits"].sole["labels"]
    segment = body["kits"].sole["arcs"].find { |a| a["name"] == "SegmentListItem" }

    on_segment = labels.select { |l| l["arc_iid"] == segment["iid"] }
    assert_equal [ "Text", "Speaker" ], on_segment.map { |l| l["name"] }
    assert_equal [ "a line", "alice" ], on_segment.map { |l| l["value"] }
    assert_empty labels.select { |l| l["arc_iid"] == segment["arc_node_iid"] }
  end

  test "a group the server was never taught about is carried through" do
    # The whole point of the graph tables: the client owns the vocabulary, so a
    # comment span reaches the drawing with no change on this side.
    sign_in_as @alice
    tree = Tree.find(@kit.tree_id)
    annotate(tree, "add", value: "40:CommentListItem,41:Arc,42:Comment")
    annotate(tree, "change", iid: 41, begi: 10, endi: 12)
    annotate(tree, "change", iid: 42, value: "noisy here")

    body = fetch
    comment = body["kits"].sole["arcs"].find { |a| a["name"] == "CommentListItem" }
    assert_equal 40, comment["iid"]
    assert_equal(
      "noisy here",
      body["kits"].sole["labels"].find { |l| l["arc_iid"] == 40 }["value"]
    )
  end

  test "the rows are snapshotted, not read from whatever was there before" do
    sign_in_as @alice
    assert_difference -> { GraphNode.count }, 2 do
      assert_difference -> { GraphArc.count }, 2 do
        assert_difference -> { GraphLabel.count }, 3 do
          fetch
        end
      end
    end
  end

  # ── reusing a snapshot ────────────────────────────────────────────────────

  test "a kit nobody has annotated since is not replayed again" do
    sign_in_as @alice
    body = fetch
    assert_equal 0, body["reused"]
    written = GraphArc.by_tree(@kit.tree_id).maximum(:created_at)

    body = fetch
    assert_equal 1, body["reused"]
    assert_equal written, GraphArc.by_tree(@kit.tree_id).maximum(:created_at),
                 "the rows should not have been rewritten"
  end

  test "the reused rows are the same rows, not an empty answer" do
    sign_in_as @alice
    fetch
    block = fetch["kits"].sole

    assert_equal [ 10, 12 ], block["nodes"].map { |n| n["iid"] }
    assert_equal 2, block["arcs"].length
    assert_equal [ "a line", "alice" ],
                 block["labels"].select { |l| l["arc_iid"] == 14 }.map { |l| l["value"] }
  end

  test "an annotation since the snapshot makes it replay again" do
    sign_in_as @alice
    fetch
    annotate(Tree.find(@kit.tree_id), "change", iid: 16, value: "a later line")

    body = fetch
    assert_equal 0, body["reused"]
    assert_equal "a later line",
                 body["kits"].sole["labels"].find { |l| l["name"] == "Text" }["value"]
  end

  test "rebuild replays a kit that was already current" do
    sign_in_as @alice
    fetch
    assert_equal 1, fetch["reused"]

    body = fetch(rebuild: 1)
    assert_equal 0, body["reused"]
  end

  test "only the stale kits are replayed, not the whole task with them" do
    sign_in_as @alice
    second = annotated_kit do |tree|
      annotate(tree, "add", value: "10:NListItem,11:N")
      annotate(tree, "change", iid: 11, docid: "b.wav", begr: 0)
      annotate(tree, "add", value: "12:NListItem,13:N")
      annotate(tree, "change", iid: 13, docid: "b.wav", begr: 2)
      annotate(tree, "add", value: "14:SegmentListItem,15:Arc,16:Text,17:Speaker")
      annotate(tree, "change", iid: 15, begi: 10, endi: 12)
      annotate(tree, "change", iid: 16, value: "elsewhere")
    end
    fetch
    untouched = GraphArc.by_tree(@kit.tree_id).maximum(:created_at)

    annotate(Tree.find(second.tree_id), "change", iid: 16, value: "changed here")
    body = fetch

    assert_equal 1, body["reused"]
    assert_equal untouched, GraphArc.by_tree(@kit.tree_id).maximum(:created_at),
                 "the kit nothing happened to should have been left alone"
    assert_equal "changed here",
                 body["kits"].find { |k| k["kit_id"] == second.id }["labels"]
                   .find { |l| l["name"] == "Text" }["value"]
  end

  test "rows are stamped from before the replay, so a concurrent write is not lost" do
    # The stamp has to mean "the log as of here". Stamped after the replay
    # instead, an annotation written while the rows were being built would date
    # older than them and be called current for ever.
    sign_in_as @alice
    began = Time.current
    fetch
    assert_operator GraphArc.by_tree(@kit.tree_id).maximum(:created_at), :>=, began
    assert_operator GraphArc.by_tree(@kit.tree_id).maximum(:created_at), :<=, Time.current
  end

  test "a kit that has never been annotated is not called current" do
    # It has a tree and no rows, so there is nothing to reuse.
    sign_in_as @alice
    bare = annotated_kit # no block, so no annotations at all
    assert_equal false, bare.graph_current?
  end

  test "a second request replaces the rows rather than adding to them" do
    sign_in_as @alice
    fetch
    assert_no_difference [ -> { GraphNode.count }, -> { GraphArc.count }, -> { GraphLabel.count } ] do
      fetch(rebuild: 1)
    end
  end

  test "an edit since the last snapshot shows up, because the log is the record" do
    sign_in_as @alice
    fetch
    annotate(Tree.find(@kit.tree_id), "change", iid: 16, value: "a different line")

    text = fetch["kits"].sole["labels"].find { |l| l["name"] == "Text" }
    assert_equal "a different line", text["value"]
  end

  test "every annotated kit in the task gets a block, in id order" do
    sign_in_as @alice
    second = annotated_kit(user: @bob, state: "done") do |tree|
      annotate(tree, "add", value: "10:NListItem,11:N")
      annotate(tree, "change", iid: 11, docid: "b.wav", begr: 0)
      annotate(tree, "add", value: "12:NListItem,13:N")
      annotate(tree, "change", iid: 13, docid: "b.wav", begr: 2)
      annotate(tree, "add", value: "14:SegmentListItem,15:Arc,16:Text,17:Speaker")
      annotate(tree, "change", iid: 15, begi: 10, endi: 12)
      annotate(tree, "change", iid: 16, value: "elsewhere")
    end

    body = fetch
    assert_equal [ @kit.id, second.id ].sort, body["kits"].map { |k| k["kit_id"] }
    assert_equal [ @bob.name, "done" ],
                 body["kits"].find { |k| k["kit_id"] == second.id }.values_at("user", "state")
  end

  # ── counting what isn't drawn ─────────────────────────────────────────────

  test "a kit nobody has opened is counted rather than dropped silently" do
    # It has no tree, so no annotations and nothing to draw. "This task has
    # forty kits and I can see one" needs an answer on the page.
    sign_in_as @alice
    Kit.create!(task_id: @task.id, kit_type_id: @kit_type.id, state: "unassigned",
                uid: "task-graph-unopened-#{SecureRandom.hex(3)}")

    body = fetch
    assert_equal 1, body["kits"].length
    assert_equal 1, body["unopened"]
    assert_equal 2, body["kit_count"]
  end

  test "the kit bound says how many were left out" do
    sign_in_as @alice
    annotated_kit do |tree|
      annotate(tree, "add", value: "10:NListItem,11:N")
      annotate(tree, "change", iid: 11, docid: "b.wav", begr: 0)
    end

    body = fetch(limit: 1)
    assert_equal 1, body["kits"].length
    assert_equal 1, body["truncated"]
    assert_equal 2, body["kit_count"]
  end

  test "limit=0 asks for the whole task" do
    sign_in_as @alice
    annotated_kit do |tree|
      annotate(tree, "add", value: "10:NListItem,11:N")
      annotate(tree, "change", iid: 11, docid: "b.wav", begr: 0)
    end

    body = fetch(limit: 0)
    assert_equal 2, body["kits"].length
    assert_equal 0, body["truncated"]
  end

  test "a task with nothing annotated draws nothing and says so plainly" do
    sign_in_as @alice
    Kit.where(task_id: @task.id).destroy_all
    body = fetch
    assert_empty body["kits"]
    assert_equal 0, body["kit_count"]
  end

  # ── who may look ──────────────────────────────────────────────────────────

  test "a task member who isn't an admin is refused" do
    sign_in_as @bob
    body = fetch
    assert_equal "You must be a task admin to do that.", body["error"]
    assert_empty body.fetch("kits", [])
  end

  test "the refusal doesn't snapshot anything" do
    sign_in_as @bob
    assert_no_difference -> { GraphArc.count } do
      fetch
    end
  end

  test "the html page renders for an admin and redirects everyone else" do
    sign_in_as @alice
    get graph_project_task_url(project_id: @alpha.id, id: @task.id)
    assert_response :success
    # The page is a mount point; the drawing is the component's.
    assert_match "task_graph", @response.body

    sign_in_as @bob
    get graph_project_task_url(project_id: @alpha.id, id: @task.id)
    assert_redirected_to root_path
  end
end
