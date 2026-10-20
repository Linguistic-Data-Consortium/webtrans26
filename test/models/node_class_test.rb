require "test_helper"

class NodeClassTest < ActiveSupport::TestCase
  test "name is required and unique (case-insensitive)" do
    nc = NodeClass.new
    assert_not nc.valid?

    seed = NodeClass.create!(name: "UniqNC-#{SecureRandom.hex(2)}")
    dup = NodeClass.new(name: seed.name.upcase)
    assert_not dup.valid?
    assert dup.errors[:name].any?
  end

  test "belongs_to parent (NodeClass)" do
    assert_equal node_classes(:root), node_classes(:arc_transcription_root).parent
  end

  # ── name parsing helpers ─────────────────────────────────────────────────

  test "name_without_root_suffix strips ':Root'" do
    assert_equal "ArcTranscription", node_classes(:arc_transcription_root).name_without_root_suffix
  end

  test "name_without_prefix returns the part after the colon" do
    assert_equal "Root", node_classes(:arc_transcription_root).name_without_prefix
    assert_equal "Root", node_classes(:root).name_without_prefix # no colon → returns full name
  end

  test "name_prefix returns the part before the colon" do
    assert_equal "ArcTranscription", node_classes(:arc_transcription_root).name_prefix
  end

  test "types walks the parent chain and tail-appends 'Node'" do
    types = node_classes(:arc_transcription_root).types
    assert_equal "ArcTranscription:Root", types.first
    assert_equal "Node", types.last
    assert_includes types, node_classes(:root).name
  end

  # ── scopes ───────────────────────────────────────────────────────────────

  test "sorted scope orders by name ASC" do
    a = NodeClass.create!(name: "Zeta:Root-#{SecureRandom.hex(2)}")
    b = NodeClass.create!(name: "Alpha:Root-#{SecureRandom.hex(2)}")
    rows = NodeClass.sorted.where(id: [a.id, b.id]).to_a
    assert_equal b, rows.first
    assert_equal a, rows.last
  end

  test "root_nodes returns NodeClasses parented to the Root NodeClass" do
    rows = NodeClass.root_nodes
    assert_includes rows, node_classes(:arc_transcription_root)
    assert_not_includes rows, node_classes(:root)
  end

  test "value and constraints serialize as Hashes" do
    nc = NodeClass.create!(
      name: "Serialize-#{SecureRandom.hex(2)}",
      parent: node_classes(:root),
      value: { "label" => "Foo" },
      constraints: { "edit" => { "x" => 1 } }
    )
    nc.reload
    assert_equal "Foo", nc.value["label"]
    assert_equal({ "x" => 1 }, nc.constraints["edit"])
    assert_equal "Foo", nc.label # convenience getter
  end
end
