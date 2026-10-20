require "test_helper"

class ClassDefTest < ActiveSupport::TestCase
  # ── validations ──────────────────────────────────────────────────────────

  test "name is required" do
    cd = ClassDef.new
    assert_not cd.valid?
    assert cd.errors[:name].any?
  end

  test "name uniqueness is case-insensitive" do
    seed = ClassDef.create!(name: "UniqueCD-#{SecureRandom.hex(2)}")
    dup = ClassDef.new(name: seed.name.upcase)
    assert_not dup.valid?
    assert dup.errors[:name].any?
  end

  test "name max length is 50" do
    cd = ClassDef.new(name: "x" * 51)
    assert_not cd.valid?
    assert cd.errors[:name].any?
  end

  # ── scopes ───────────────────────────────────────────────────────────────

  test "sorted scope orders by name ASC" do
    a = ClassDef.create!(name: "ZetaSort-#{SecureRandom.hex(2)}")
    b = ClassDef.create!(name: "AlphaSort-#{SecureRandom.hex(2)}")
    rows = ClassDef.sorted.where(id: [a.id, b.id]).to_a
    assert_equal b, rows.first
    assert_equal a, rows.last
  end

  # ── new_root ─────────────────────────────────────────────────────────────

  test "new_root creates a Tree linked to this ClassDef and stamps original_id" do
    cd = ClassDef.create!(name: "RootMaker-#{SecureRandom.hex(2)}")
    tree = nil
    assert_difference -> { Tree.count }, 1 do
      tree = cd.new_root
    end
    assert_equal cd.id, tree.class_def_id
    assert_equal cd.id, cd.reload.original_id
    assert_equal cd.original_id, tree.version
    assert tree.uid.present?
    assert_equal 0, tree.last_iid.to_i
  end

  # ── basic_info ───────────────────────────────────────────────────────────

  test "basic_info returns metadata for the class def" do
    cd = ClassDef.create!(name: "Info-#{SecureRandom.hex(2)}")
    info = cd.basic_info
    assert_equal cd.id, info[:class_def_id]
    assert_equal cd.name, info[:name]
    assert info[:def].present?
    assert_kind_of Hash, JSON.parse(info[:def])
  end
end
