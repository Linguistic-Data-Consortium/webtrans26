require "test_helper"

class AnnotationTest < ActiveSupport::TestCase
  setup do
    @class_def = ClassDef.create!(name: "AnnTest-#{SecureRandom.hex(3)}")
    @tree = Tree.create!(uid: "ann-tree-#{SecureRandom.hex(3)}", class_def: @class_def, version: 1)
    @user = users(:alice)
    @task = tasks(:alpha_task_one)
  end

  def annotate(message, **attributes)
    Annotation.create!(
      { tree_id: @tree.id, task_id: @task.id, user_id: @user.id, message: message, last_iid: "0" }
        .merge(attributes)
    )
  end

  # ── the log has no side effects ─────────────────────────────────────────

  # Annotation#apply used to write and repoint rows in a nodes table as each
  # annotation was created. That table is gone; the readers replay the log
  # (NodeDerivation), so an annotation is only ever a log row.
  test "an annotation no longer responds to apply" do
    assert_not Annotation.new.respond_to?(:apply)
  end

  test "creating annotations only writes annotations" do
    assert_difference -> { Annotation.count }, 3 do
      annotate("add", value: "0:Root,1:Child")
      annotate("change", iid: 1, value: "text")
      annotate("delete", iid: 1)
    end
  end

  # ── node_value: the shape a node takes from this annotation ─────────────

  test "a real-time span with both ends is a docid/beg/end value" do
    value = annotate("change", iid: 1, docid: "a.wav", begr: 1.25, endr: 3.5).node_value
    assert_equal({ docid: "a.wav", beg: 1.25, end: 3.5 }, value)
  end

  test "a real-time span with only a beg is a single timestamp" do
    value = annotate("change", iid: 1, docid: "a.wav", begr: 1.25).node_value
    assert_equal({ docid: "a.wav", beg: 1.25 }, value)
  end

  test "integer beg/end are node pointers, not times" do
    assert_equal({ beg: 10, end: 12 }, annotate("change", iid: 1, begi: 10, endi: 12).node_value)
  end

  test "text carries its docid and offsets" do
    value = annotate("change", iid: 1, docid: "doc", begi: 3, endi: 9, text: "hello").node_value
    assert_equal({ docid: "doc", beg: 3, end: 9, text: "hello" }, value)
  end

  test "a source reference is just the source id" do
    assert_equal({ source_id: 7 }, annotate("change", iid: 1, source_id: 7).node_value)
  end

  test "anything else is a plain value" do
    assert_equal({ value: "alice" }, annotate("change", iid: 1, value: "alice").node_value)
    assert_equal({ value: nil }, annotate("change", iid: 1).node_value)
  end

  test "a span that also carries a value keeps both" do
    value = annotate("change", iid: 1, docid: "a.wav", begr: 1.0, endr: 2.0, value: "tagged").node_value
    assert_equal({ docid: "a.wav", beg: 1.0, end: 2.0, value: "tagged" }, value)
  end

  # A node with no annotation of its own points at the id-0 placeholder; the
  # derivation gives it NO_VALUE rather than looking anything up.
  test "the placeholder stands for no value" do
    assert_equal({ value: nil }, Annotation::NO_VALUE)
  end
end
