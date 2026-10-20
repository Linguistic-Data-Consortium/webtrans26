require "test_helper"

# Kit#client_nodes and Kit#snapshot build their nodes from the annotation log.
# These tests write a log the way the editor does and check what each reader
# produces from it.
class KitDerivedNodesTest < ActiveSupport::TestCase
  setup do
    @placeholder = Annotation.where(id: 0).first_or_create # see NodeDerivationTest
    @class_def = ClassDef.create!(name: "ArcTranscription")
    @tree = Tree.create!(uid: "derived-#{SecureRandom.hex(3)}", class_def: @class_def, version: 2)
    @task = tasks(:alpha_task_one)
    @user = users(:alice)
    @kit = Kit.create!(
      task_id: @task.id, kit_type_id: @task.kit_type_id, tree_id: @tree.id,
      state: "done", uid: "derived-kit-#{SecureRandom.hex(3)}"
    )
  end

  def annotate(message, **attributes)
    Annotation.create!(
      { tree_id: @tree.id, task_id: @task.id, user_id: @user.id, message: message, last_iid: "0" }
        .merge(attributes)
    )
  end

  # One transcript segment: two N nodes carrying the times, then the segment
  # subtree whose Arc points at those two N iids.
  def add_segment(base, beg_time, end_time, text, speaker)
    annotate("add", value: "#{base}:NListItem,#{base + 1}:N")
    annotate("change", iid: base + 1, docid: "a.wav", begr: beg_time)
    annotate("add", value: "#{base + 2}:NListItem,#{base + 3}:N")
    annotate("change", iid: base + 3, docid: "a.wav", begr: end_time)

    annotate("add", value: "#{base + 4}:SegmentListItem,#{base + 5}:Arc,#{base + 6}:Text,#{base + 7}:Speaker")
    # The Arc points at the two NListItems (not the N nodes): snapshot hangs each
    # N's time on its parent, then reads it back through the Arc's endpoints.
    annotate("change", iid: base + 5, begi: base, endi: base + 2)
    annotate("change", iid: base + 6, value: text)
    annotate("change", iid: base + 7, value: speaker)
  end

  def segment_rows
    Segment.where(tree_id: @tree.id).order(:iid).map do |s|
      [ s.iid, s.begn, s.endn, s.btime.to_f, s.etime.to_f, s.text, s.speaker ]
    end
  end

  # ── snapshot ─────────────────────────────────────────────────────────────

  test "snapshot writes one segment row per transcribed segment" do
    add_segment(10, 1.25, 3.5, "first line", "alice")
    add_segment(20, 4.0, 6.75, "second line", "bob")
    @kit.snapshot

    assert_equal [
      [ 14, 10, 12, 1.25, 3.5, "first line", "alice" ],
      [ 24, 20, 22, 4.0, 6.75, "second line", "bob" ]
    ], segment_rows
  end

  test "snapshot is idempotent — rerunning replaces rather than duplicates" do
    add_segment(10, 1.25, 3.5, "first line", "alice")
    @kit.snapshot
    once = segment_rows
    @kit.snapshot
    assert_equal once, segment_rows
  end

  # The group vocabulary is the client's, not the database's: an "add" can name
  # any group, and the server logs and replays it without knowing what it means.
  # This projection is the readable transcript — segments and sections — so a
  # group it doesn't recognise has to pass through it untouched rather than stop
  # it. It runs per kit from KitsController#all, so raising here would break the
  # dashboard and the downloads for every kit in the task.
  test "snapshot ignores a group the client invented" do
    add_segment(10, 1.25, 3.5, "first line", "alice")
    # "a simple span with one label", the shape a comment would take
    annotate("add", value: "30:CommentListItem,31:Arc,32:Comment")
    annotate("change", iid: 31, begi: 10, endi: 12)
    annotate("change", iid: 32, value: "check this bit")

    assert_nothing_raised { @kit.snapshot }
    assert_equal [ [ 14, 10, 12, 1.25, 3.5, "first line", "alice" ] ], segment_rows
    assert_equal 0, Section.where(tree_id: @tree.id).count
  end

  # …and the general projection carries it, which is where it belongs.
  test "the graph projection keeps the invented group" do
    add_segment(10, 1.25, 3.5, "first line", "alice")
    annotate("add", value: "30:CommentListItem,31:Arc,32:Comment")
    annotate("change", iid: 31, begi: 10, endi: 12)
    annotate("change", iid: 32, value: "check this bit")

    graph = @kit.graph_projection
    assert_equal %w[ SegmentListItem CommentListItem ], graph[:arcs].map { |a| a[:name] }
    comment = graph[:arcs].find { |a| a[:name] == "CommentListItem" }
    assert_equal [ 10, 12 ], [ comment[:beg_iid], comment[:end_iid] ], "it spans the same anchors"
    assert_equal [ { iid: 32, arc_iid: 30, name: "Comment", value: "check this bit" } ],
      graph[:labels].select { |l| l[:arc_iid] == 30 }
  end

  test "the segments carry the times and text the log holds" do
    add_segment(10, 1.25, 3.5, "first line", "alice")
    @kit.snapshot

    row = Segment.find_by(tree_id: @tree.id)
    assert_equal 1.25, row.btime.to_f
    assert_equal 3.5, row.etime.to_f
    assert_equal "first line", row.text
    assert_equal "alice", row.speaker
    assert_equal 10, row.begn, "begn is the NListItem the Arc points at"
  end

  test "a deleted segment is absent from the snapshot" do
    add_segment(10, 1.0, 2.0, "kept", "alice")
    add_segment(20, 3.0, 4.0, "removed", "bob")
    annotate("delete", iid: 24) # the second SegmentListItem
    @kit.snapshot

    assert_equal [ "kept" ], Segment.where(tree_id: @tree.id).pluck(:text)
  end

  test "an edit is reflected, taking the latest annotation" do
    add_segment(10, 1.0, 2.0, "before", "alice")
    annotate("change", iid: 16, value: "after") # the Text node

    @kit.snapshot
    assert_equal [ "after" ], Segment.where(tree_id: @tree.id).pluck(:text)
  end

  # ── client payload ───────────────────────────────────────────────────────

  # work/other.js's init2 reads exactly these five fields off each node.
  test "client_nodes carries the fields the client reads" do
    add_segment(10, 1.0, 2.0, "words", "alice")
    nodes, values = @kit.client_nodes

    segment = nodes.find { |n| n[:name] == "SegmentListItem" }
    assert_equal 14, segment[:iid]
    assert_equal 2, segment[:level]
    assert_nil segment[:parent_iid]

    text = nodes.find { |n| n[:name] == "Text" }
    assert_equal 14, text[:parent_iid]
    assert_equal 3, text[:level]
    assert_includes values.map(&:id), text[:annotation_id]
    assert_equal "words", values.find { |v| v.id == text[:annotation_id] }.value
  end

  test "node_values includes the id-0 placeholder when a node still points at it" do
    annotate("add", value: "10:SegmentListItem,11:Arc") # Arc never gets a change
    _, values = @kit.client_nodes
    assert_includes values.map(&:id), 0
  end

  test "each node's value is the shape its annotation implies" do
    add_segment(10, 1.0, 2.0, "words", "alice")
    derived = NodeDerivation.for_tree(@tree.id)

    # N node: a single real timestamp
    assert_equal({ docid: "a.wav", beg: 1.0 }, derived.value_for(derived.nodes[11]))
    # Arc: integer pointers at the two NListItems
    assert_equal({ beg: 10, end: 12 }, derived.value_for(derived.nodes[15]))
    # Text and Speaker: plain values
    assert_equal({ value: "words" }, derived.value_for(derived.nodes[16]))
    assert_equal({ value: "alice" }, derived.value_for(derived.nodes[17]))
  end

  test "a kit with no tree still snapshots to nothing" do
    kit = Kit.create!(task_id: @task.id, kit_type_id: @task.kit_type_id, state: "unassigned",
                      uid: "no-tree-#{SecureRandom.hex(3)}")
    assert_nothing_raised { kit.snapshot }
  end
end
