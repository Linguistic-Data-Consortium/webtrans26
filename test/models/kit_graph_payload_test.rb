require "test_helper"

# Kit#graph_payload rebuilds the payload the annotation tool loads with, but out
# of graph_nodes / graph_arcs / graph_labels instead of the annotation log. Two
# independent descriptions of the same tree, so one can check the other — for a
# kit whose snapshot is current.
class KitGraphPayloadTest < ActiveSupport::TestCase
  setup do
    Annotation.where(id: 0).first_or_create
    @class_def = ClassDef.where(name: "ArcTranscription").first_or_create!
    # to_hash reads class_def through the kit type's node class, so the kit
    # needs the real chain rather than a bare fixture.
    root = NodeClass.where(name: "ArcTranscription:Root").first_or_create!(class_def: @class_def)
    @kit_type = KitType.create!(name: "gp-#{SecureRandom.hex(3)}", node_class: root)
    @tree = Tree.create!(uid: "gp-#{SecureRandom.hex(3)}", class_def: @class_def, version: 2)
    @task = tasks(:alpha_task_one)
    @user = users(:alice)
    @kit = Kit.create!(
      task_id: @task.id, kit_type_id: @kit_type.id, tree_id: @tree.id,
      user_id: @user.id, state: "done", uid: "gp-kit-#{SecureRandom.hex(3)}"
    )
  end

  def annotate(message, **attributes)
    Annotation.create!(
      { tree_id: @tree.id, task_id: @task.id, user_id: @user.id, message: message, last_iid: "0" }
        .merge(attributes)
    )
  end

  def add_segment(base, beg_time, end_time, text, speaker)
    annotate("add", value: "#{base}:NListItem,#{base + 1}:N")
    annotate("change", iid: base + 1, docid: "a.wav", begr: beg_time)
    annotate("add", value: "#{base + 2}:NListItem,#{base + 3}:N")
    annotate("change", iid: base + 3, docid: "a.wav", begr: end_time)
    annotate("add", value: "#{base + 4}:SegmentListItem,#{base + 5}:Arc,#{base + 6}:Text,#{base + 7}:Speaker")
    annotate("change", iid: base + 5, begi: base, endi: base + 2)
    annotate("change", iid: base + 6, value: text)
    annotate("change", iid: base + 7, value: speaker)
  end

  # The five fields work/other.js's init2 reads off each node.
  def node_shapes(payload)
    payload["nodes"].map { |n| [ n[:iid], n[:name], n[:parent_iid], n[:level] ] }.sort_by { |f| f.first }
  end

  # What each node ends up pointing at. The two payloads key values differently
  # — the log by annotation id, the graph by the node's own iid — so compare
  # the resolved value rather than the id.
  def resolved_values(payload)
    by_id = payload["node_values"].index_by { |v| v[:id] }
    payload["nodes"].to_h do |n|
      v = by_id[n[:annotation_id]]
      [ n[:iid], v && [ v[:value], v[:docid], v[:beg], v[:end] ] ]
    end
  end

  # ── the two payloads agree ───────────────────────────────────────────────

  test "the graph payload describes the same tree as the log payload" do
    add_segment(10, 1.25, 3.5, "first line", "alice")
    add_segment(20, 4.0, 6.5, "second line", "bob")
    @kit.graph_snapshot

    log = @kit.to_hash(false, "deep")
    graph = @kit.graph_payload

    assert_equal log.keys.sort, graph.keys.sort
    assert_equal node_shapes(log), node_shapes(graph)
    assert_equal resolved_values(log), resolved_values(graph)
    assert_equal log["last_iid"], graph["last_iid"]
  end

  test "they still agree after an edit and a rebuild" do
    add_segment(10, 1.0, 2.0, "before", "alice")
    annotate("change", iid: 16, value: "after")
    @kit.graph_snapshot

    assert_equal resolved_values(@kit.to_hash(false, "deep")), resolved_values(@kit.graph_payload)
  end

  test "they still agree after a delete and a rebuild" do
    add_segment(10, 1.0, 2.0, "kept", "alice")
    add_segment(20, 3.0, 4.0, "removed", "bob")
    annotate("delete", iid: 24)
    @kit.graph_snapshot

    log = @kit.to_hash(false, "deep")
    assert_equal node_shapes(log), node_shapes(@kit.graph_payload)
    assert_equal resolved_values(log), resolved_values(@kit.graph_payload)
  end

  # Regression: last_iid is where the client resumes handing out iids. Deleting
  # the newest group leaves the graph's highest iid below the last one issued,
  # so taking the maximum from the tables would hand out iids already used.
  test "last_iid is the high-water mark, not the highest iid still in the graph" do
    add_segment(10, 1.0, 2.0, "kept", "alice")
    add_segment(20, 3.0, 4.0, "removed", "bob")
    annotate("delete", iid: 24)
    @kit.graph_snapshot

    graph = @kit.graph_payload
    assert_equal 27, graph["last_iid"], "the last add issued iids up to 27"
    assert_operator graph["nodes"].map { |n| n[:iid] }.max, :<, graph["last_iid"]
  end

  # ── what the graph payload adds ──────────────────────────────────────────

  test "nodes carry the graph rows they came from, and arcs their arc iid" do
    add_segment(10, 1.0, 2.0, "words", "alice")
    @kit.graph_snapshot
    nodes = @kit.graph_payload["nodes"]

    text = nodes.find { |n| n[:name] == "Text" }
    assert_equal 15, text[:arc_node_iid], "labels name the Arc of the span they're on"
    assert text[:graph_id].present?, "and the graph_labels row they came from"

    anchor = nodes.find { |n| n[:name] == "NListItem" }
    assert anchor[:graph_id].present?
    assert_nil anchor[:arc_node_iid]
  end

  test "a list item's value is the group string, rebuilt from the rows" do
    add_segment(10, 1.0, 2.0, "words", "alice")
    @kit.graph_snapshot

    graph = @kit.graph_payload
    item = graph["nodes"].find { |n| n[:name] == "SegmentListItem" }
    value = graph["node_values"].find { |v| v[:id] == item[:annotation_id] }
    assert_equal "14:SegmentListItem,15:Arc,16:Text,17:Speaker", value[:value]
  end

  # ── the in-memory form: same payload, nothing written ────────────────────

  test "the in-memory payload matches the stored one" do
    add_segment(10, 1.25, 3.5, "first line", "alice")
    add_segment(20, 4.0, 6.5, "second line", "bob")
    @kit.graph_snapshot

    stored = @kit.graph_payload
    memory = @kit.graph_memory_payload
    without_row_ids = ->(p) { p["nodes"].map { |n| n.except(:graph_id) }.sort_by { |n| n[:iid] } }

    assert_equal without_row_ids.call(stored), without_row_ids.call(memory)
    assert_equal stored["node_values"].sort_by { |v| v[:id] }, memory["node_values"].sort_by { |v| v[:id] }
    assert_equal stored["last_iid"], memory["last_iid"]
  end

  test "it needs no snapshot and writes nothing" do
    add_segment(10, 1.25, 3.5, "first line", "alice")

    assert_no_difference -> { GraphNode.count + GraphArc.count + GraphLabel.count } do
      payload = @kit.graph_memory_payload
      assert_equal 8, payload["nodes"].size, "the tree is there without any stored rows"
      assert_equal "graph_memory", payload["payload_source"]
    end
  end

  test "it follows the log, where the stored form follows the last snapshot" do
    add_segment(10, 1.0, 2.0, "before", "alice")
    @kit.graph_snapshot
    annotate("change", iid: 16, value: "after")

    assert_equal "after", resolved_values(@kit.graph_memory_payload)[16].first
    assert_equal "before", resolved_values(@kit.graph_payload)[16].first
  end

  test "the same rows underlie both: graph_projection writes nothing" do
    add_segment(10, 1.0, 2.0, "words", "alice")

    assert_no_difference -> { GraphNode.count + GraphArc.count + GraphLabel.count } do
      projection = @kit.graph_projection
      assert_equal 2, projection[:nodes].size
      assert_equal 1, projection[:arcs].size
      assert_equal 2, projection[:labels].size
    end

    @kit.graph_snapshot
    assert_equal 2, GraphNode.by_tree(@tree.id).count, "and snapshot stores exactly those"
  end

  # ── it reads the tables, and says so when they're empty ──────────────────

  test "with no snapshot taken the tree section is empty" do
    add_segment(10, 1.0, 2.0, "words", "alice")
    payload = @kit.graph_payload

    assert_empty payload["nodes"]
    assert_empty payload["node_values"]
    assert_equal @kit.to_hash(false, "deep")["source"], payload["source"], "the kit metadata is still there"
  end

  test "it reads what was stored, not what the log says now" do
    add_segment(10, 1.0, 2.0, "before", "alice")
    @kit.graph_snapshot
    annotate("change", iid: 16, value: "after") # not snapshotted

    graph = @kit.graph_payload
    text_node = graph["nodes"].find { |n| n[:name] == "Text" }
    value = graph["node_values"].find { |v| v[:id] == text_node[:annotation_id] }
    assert_equal "before", value[:value]
    assert_equal "after", resolved_values(@kit.to_hash(false, "deep"))[16].first
  end
end
