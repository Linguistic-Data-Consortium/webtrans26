require "test_helper"

# Kit#graph_snapshot is a second projection of the annotation log, alongside the
# segments/sections one #snapshot writes. An "add" group becomes either an
# anchor (GraphNode, from "1:NListItem,2:N") or a span between two anchors
# (GraphArc), and each of the span's other children becomes a GraphLabel — so a
# segment's text and a section's name don't share columns.
class KitGraphSnapshotTest < ActiveSupport::TestCase
  setup do
    Annotation.where(id: 0).first_or_create
    @class_def = ClassDef.create!(name: "ArcTranscription")
    @tree = Tree.create!(uid: "graph-#{SecureRandom.hex(3)}", class_def: @class_def, version: 2)
    @task = tasks(:alpha_task_one)
    @user = users(:alice)
    @kit = Kit.create!(
      task_id: @task.id, kit_type_id: @task.kit_type_id, tree_id: @tree.id,
      state: "done", uid: "graph-kit-#{SecureRandom.hex(3)}"
    )
  end

  def annotate(message, **attributes)
    Annotation.create!(
      { tree_id: @tree.id, task_id: @task.id, user_id: @user.id, message: message, last_iid: "0" }
        .merge(attributes)
    )
  end

  # Two anchors, then a segment spanning them — the shape the editor writes.
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

  def add_section(base, beg_iid, end_iid, label)
    annotate("add", value: "#{base}:SectionListItem,#{base + 1}:Arc,#{base + 2}:Name")
    annotate("change", iid: base + 1, begi: beg_iid, endi: end_iid)
    annotate("change", iid: base + 2, value: label)
  end

  # ── anchors ──────────────────────────────────────────────────────────────

  test "each NListItem/N pair becomes one graph_nodes row" do
    add_segment(10, 1.25, 3.5, "first", "alice")
    @kit.graph_snapshot

    nodes = GraphNode.by_tree(@tree.id).in_time_order
    assert_equal 2, nodes.count, "one row per anchor, not one per node"
    assert_equal [ 10, 12 ], nodes.map(&:iid)
    assert_equal [ 11, 13 ], nodes.map(&:n_iid), "the N child is recorded on the same row"
    assert_equal [ 1.25, 3.5 ], nodes.map { |n| n.time.to_f }
    assert_equal [ "a.wav", "a.wav" ], nodes.map(&:docid)
  end

  # ── spans ────────────────────────────────────────────────────────────────

  test "a segment group becomes one structural graph_arcs row" do
    add_segment(10, 1.25, 3.5, "first line", "alice")
    @kit.graph_snapshot

    arc = GraphArc.by_tree(@tree.id).sole
    assert_equal 14, arc.iid
    assert_equal "SegmentListItem", arc.name
    assert_equal 15, arc.arc_node_iid, "arc_node_iid is the Arc child, not the arc's own identity"
    assert_equal [ 10, 12 ], [ arc.beg_iid, arc.end_iid ], "the Arc's endpoints are anchor iids"
    assert_not arc.respond_to?(:text), "a span carries no labels of its own"
    assert_not arc.respond_to?(:speaker)
  end

  test "a segment's other children become labels on that arc" do
    add_segment(10, 1.25, 3.5, "first line", "alice")
    @kit.graph_snapshot

    labels = GraphLabel.by_tree(@tree.id).for_arc(14).order(:iid)
    assert_equal [ "Text", "Speaker" ], labels.map(&:name)
    assert_equal [ "first line", "alice" ], labels.map(&:value)
    assert_equal [ 16, 17 ], labels.map(&:iid), "each label keeps its own node's iid"
    # The two columns spelled alike name different nodes: a label's arc_iid is
    # the arc's own iid, never the Arc child that arc_node_iid points at.
    arc = GraphArc.by_tree(@tree.id).sole
    assert_equal [ arc.iid, arc.iid ], labels.map(&:arc_iid)
    assert_not_equal arc.arc_node_iid, labels.first.arc_iid
  end

  test "a section is the same shape: an arc plus a label" do
    add_segment(10, 1.0, 2.0, "words", "alice")
    add_section(30, 10, 12, "intro")
    @kit.graph_snapshot

    section = GraphArc.by_tree(@tree.id).sections.sole
    assert_equal [ 10, 12 ], [ section.beg_iid, section.end_iid ]

    label = GraphLabel.by_tree(@tree.id).for_arc(section.iid).sole
    assert_equal "Name", label.name
    assert_equal "intro", label.value
    assert_equal 1, GraphArc.by_tree(@tree.id).segments.count
  end

  test "segments and sections keep their labels apart" do
    add_segment(10, 1.0, 2.0, "words", "alice")
    add_section(30, 10, 12, "intro")
    @kit.graph_snapshot

    segment_arc = GraphArc.by_tree(@tree.id).segments.sole
    section_arc = GraphArc.by_tree(@tree.id).sections.sole
    assert_equal %w[ Text Speaker ], segment_arc.labels.order(:iid).map(&:name)
    assert_equal %w[ Name ], section_arc.labels.map(&:name)
  end

  test "anchors and spans are counted separately" do
    add_segment(10, 1.0, 2.0, "one", "alice")
    add_segment(20, 3.0, 4.0, "two", "bob")
    result = @kit.graph_snapshot

    assert_equal 4, result[:nodes].size
    assert_equal 2, result[:arcs].size
    assert_equal 4, result[:labels].size, "Text and Speaker for each segment"
  end

  # ── rebuild semantics, as #snapshot has ──────────────────────────────────

  test "rebuilding replaces the tree's rows rather than duplicating them" do
    add_segment(10, 1.0, 2.0, "one", "alice")
    @kit.graph_snapshot
    first = GraphArc.by_tree(@tree.id).map(&:iid)

    @kit.graph_snapshot
    assert_equal first, GraphArc.by_tree(@tree.id).map(&:iid)
    assert_equal 2, GraphNode.by_tree(@tree.id).count
    assert_equal 2, GraphLabel.by_tree(@tree.id).count, "labels are rewritten, not appended"
  end

  test "an edit is picked up on the next rebuild" do
    add_segment(10, 1.0, 2.0, "before", "alice")
    @kit.graph_snapshot
    annotate("change", iid: 16, value: "after")     # the Text child
    annotate("change", iid: 11, docid: "a.wav", begr: 1.75) # move the first anchor

    @kit.graph_snapshot
    assert_equal "after", GraphLabel.by_tree(@tree.id).named("Text").sole.value
    assert_equal 1.75, GraphNode.find_by(tree_id: @tree.id, iid: 10).time.to_f
  end

  test "a deleted segment disappears from the rows" do
    add_segment(10, 1.0, 2.0, "kept", "alice")
    add_segment(20, 3.0, 4.0, "removed", "bob")
    annotate("delete", iid: 24)                     # the second SegmentListItem
    @kit.graph_snapshot

    assert_equal [ "kept" ], GraphLabel.by_tree(@tree.id).named("Text").map(&:value)
    assert_equal 1, GraphArc.by_tree(@tree.id).count
    assert_equal 4, GraphNode.by_tree(@tree.id).count, "its anchors are untouched"
  end

  test "one tree's rebuild leaves another tree's rows alone" do
    other_tree = Tree.create!(uid: "graph-2-#{SecureRandom.hex(3)}", class_def: @class_def, version: 2)
    GraphNode.create!(tree_id: other_tree.id, iid: 99, n_iid: 100, time: 9.0)
    add_segment(10, 1.0, 2.0, "one", "alice")

    @kit.graph_snapshot
    assert_equal 1, GraphNode.by_tree(other_tree.id).count
  end

  # ── what comes back for display ──────────────────────────────────────────

  test "the returned rows carry each span's times, resolved through its anchors" do
    add_segment(10, 1.25, 3.5, "first line", "alice")
    result = @kit.graph_snapshot

    row = result[:arcs].sole
    assert_equal 1.25, row[:beg]
    assert_equal 3.5, row[:end]
    # …and what it's labelled with comes back keyed to that arc.
    text = result[:labels].find { |l| l[:name] == "Text" }
    assert_equal row[:iid], text[:arc_iid]
    assert_equal "first line", text[:value]
  end

  test "anchors come back in time order" do
    add_segment(20, 5.0, 6.0, "later", "alice")
    add_segment(10, 1.0, 2.0, "earlier", "bob")
    times = @kit.graph_snapshot[:nodes].map { |n| n[:time] }
    assert_equal times.sort, times
  end

  test "graph_rows reads the persisted rows without rebuilding" do
    add_segment(10, 1.0, 2.0, "one", "alice")
    @kit.graph_snapshot
    GraphArc.by_tree(@tree.id).delete_all
    assert_empty @kit.graph_rows[:arcs], "reads what is there, rather than rebuilding it"
    assert_equal 2, @kit.graph_rows[:nodes].size
    assert_equal 2, @kit.graph_rows[:labels].size
  end

  test "a kit with no tree yields nothing and writes nothing" do
    kit = Kit.create!(task_id: @task.id, kit_type_id: @task.kit_type_id, state: "unassigned",
                      uid: "graph-no-tree-#{SecureRandom.hex(3)}")
    assert_no_difference -> { GraphNode.count + GraphArc.count + GraphLabel.count } do
      assert_equal({ nodes: [], arcs: [], labels: [] }, kit.graph_snapshot)
    end
  end
end
