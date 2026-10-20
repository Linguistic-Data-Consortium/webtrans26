require "test_helper"

# The log is the only record of a tree's shape, so these tests write one and
# check the graph replayed from it — what it contains, and the anomalies a log
# can carry that the old nodes table couldn't have held.
class NodeDerivationTest < ActiveSupport::TestCase
  setup do
    # Valueless children point at the id-0 placeholder row that db/seeds.rb
    # creates; the client payload includes it. Production has it, the test
    # database doesn't.
    @placeholder = Annotation.where(id: 0).first_or_create
    @class_def = ClassDef.create!(name: "DeriveTest-#{SecureRandom.hex(3)}")
    @tree = Tree.create!(uid: "derive-#{SecureRandom.hex(3)}", class_def: @class_def, version: 2)
    @user = users(:alice)
    @task = tasks(:alpha_task_one)
  end

  def annotate(message, iid: nil, value: nil, last_iid: "0")
    Annotation.create!(
      tree_id: @tree.id, task_id: @task.id, user_id: @user.id,
      message: message, iid: iid, value: value, last_iid: last_iid
    )
  end

  # One segment, the way the editor writes it: an add for the list item and its
  # three children, then a change per child.
  def add_segment(base_iid)
    add = annotate("add", value: "#{base_iid}:SegmentListItem,#{base_iid + 1}:Arc,#{base_iid + 2}:Text,#{base_iid + 3}:Speaker")
    annotate("change", iid: base_iid + 1, value: nil)
    annotate("change", iid: base_iid + 2, value: "some words")
    annotate("change", iid: base_iid + 3, value: "alice")
    add
  end

  def derived_names
    NodeDerivation.for_tree(@tree.id).nodes.each_value.map { |n| n[:name] }
  end

  # ── what the log replays to ──────────────────────────────────────────────

  test "one add yields the list item and its three children" do
    add_segment(10)
    assert_equal %w[ SegmentListItem Arc Text Speaker ], derived_names
  end

  test "several segments, changes and a delete leave the right graph" do
    add_segment(10)
    add_segment(20)
    annotate("change", iid: 12, value: "corrected words") # edit the first Text
    annotate("delete", iid: 20)                           # remove the second segment
    add_segment(30)

    result = NodeDerivation.for_tree(@tree.id)
    assert_equal [ 10, 11, 12, 13, 30, 31, 32, 33 ], result.nodes.keys.sort
    assert_equal "corrected words", result.value_for(result.nodes[12])[:value]
    assert result.ok?, result.anomalies.inspect
  end

  test "messages that never described a node are ignored" do
    annotate("new")
    add_segment(10)
    annotate("done")
    assert_equal %w[ SegmentListItem Arc Text Speaker ], derived_names
    assert NodeDerivation.for_tree(@tree.id).ok?
  end

  test "derivation reports no anomalies for a well-formed log" do
    add_segment(10)
    assert NodeDerivation.for_tree(@tree.id).ok?
  end

  # ── the derived shape ────────────────────────────────────────────────────

  test "the list item is level 2 and its children level 3, indexed in order" do
    add = add_segment(10)
    nodes = NodeDerivation.for_tree(@tree.id).nodes

    assert_equal %w[ SegmentListItem Arc Text Speaker ], nodes.values.map { |n| n[:name] }
    assert_equal [ 2, 3, 3, 3 ], nodes.values.map { |n| n[:level] }
    assert_equal [ nil, 0, 1, 2 ], nodes.values.map { |n| n[:index] }
    assert_equal [ nil, 10, 10, 10 ], nodes.values.map { |n| n[:parent_iid] }
    assert_equal add.id, nodes[10][:annotation_id], "the list item carries the add"
  end

  test "a change repoints the node at the newest annotation" do
    add_segment(10)
    latest = annotate("change", iid: 12, value: "newest")
    assert_equal latest.id, NodeDerivation.for_tree(@tree.id).nodes[12][:annotation_id]
  end

  test "a child with no change still points at the id-0 placeholder" do
    annotate("add", value: "10:SegmentListItem,11:Arc")
    assert_equal 0, NodeDerivation.for_tree(@tree.id).nodes[11][:annotation_id]
  end

  test "deleting a list item takes its children with it" do
    add_segment(10)
    add_segment(20)
    annotate("delete", iid: 10)
    nodes = NodeDerivation.for_tree(@tree.id).nodes
    assert_equal [ 20, 21, 22, 23 ], nodes.keys.sort
  end

  # ── anomalies (things the log can say that the table couldn't hold) ──────

  test "a change for an unknown iid is reported, not applied" do
    result = NodeDerivation.replay([ Annotation.new(id: 1, message: "change", iid: 99) ])
    assert_empty result.nodes
    assert_match(/'change' for unknown iid 99/, result.anomalies.first)
  end

  test "a delete for an unknown iid is reported" do
    result = NodeDerivation.replay([ Annotation.new(id: 1, message: "delete", iid: 99) ])
    assert_match(/'delete' for unknown iid 99/, result.anomalies.first)
  end

  test "an iid added twice is reported — the unique index would have refused it" do
    result = NodeDerivation.replay([
      Annotation.new(id: 1, message: "add", value: "10:SegmentListItem"),
      Annotation.new(id: 2, message: "add", value: "10:SegmentListItem")
    ])
    assert_match(/iid 10 added twice/, result.anomalies.first)
  end

  test "an add with no value is reported" do
    result = NodeDerivation.replay([ Annotation.new(id: 1, message: "add", value: nil) ])
    assert_empty result.nodes
    assert_match(/'add' with no children/, result.anomalies.first)
  end

  test "a malformed child is skipped and reported" do
    result = NodeDerivation.replay([ Annotation.new(id: 1, message: "add", value: "10:Root,rubbish") ])
    assert_equal [ 10 ], result.nodes.keys
    assert_match(/malformed child/, result.anomalies.first)
  end

  # ── several trees at once ────────────────────────────────────────────────

  test "for_trees derives each tree from one query" do
    other_tree = Tree.create!(uid: "derive-2-#{SecureRandom.hex(3)}", class_def: @class_def, version: 2)
    add_segment(10)
    Annotation.create!(tree_id: other_tree.id, task_id: @task.id, user_id: @user.id,
                       message: "add", last_iid: "0", value: "40:SegmentListItem,41:Text")

    results = NodeDerivation.for_trees([ @tree.id, other_tree.id ])
    assert_equal [ 10, 11, 12, 13 ], results[@tree.id].nodes.keys.sort
    assert_equal [ 40, 41 ], results[other_tree.id].nodes.keys.sort
  end

  test "for_trees on no trees is empty, and skips nils" do
    assert_equal({}, NodeDerivation.for_trees([]))
    assert_equal({}, NodeDerivation.for_trees([ nil ]))
  end

  test "a tree with no annotations derives to nothing" do
    result = NodeDerivation.for_tree(@tree.id)
    assert_empty result.nodes
    assert result.ok?
  end

  test "tree_ids covers every tree the log knows about" do
    add_segment(10)
    assert_includes NodeDerivation.tree_ids, @tree.id
  end
end
