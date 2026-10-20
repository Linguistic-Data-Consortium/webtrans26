require "test_helper"

class TreeTest < ActiveSupport::TestCase
  setup do
    @class_def = ClassDef.create!(name: "TreeTest-#{SecureRandom.hex(3)}")
    @tree = Tree.create!(uid: "tt-#{SecureRandom.hex(3)}", class_def: @class_def, version: 1)
  end

  test "has_many kits; belongs_to class_def" do
    assert_respond_to @tree, :kits
    assert_equal @class_def, @tree.class_def
  end

  # A tree's shape comes from replaying its annotations, not from an
  # association — the nodes table and the in-memory graph built from it are
  # both gone.
  test "no longer carries a node graph of its own" do
    assert_not @tree.respond_to?(:nodes)
    assert_not @tree.respond_to?(:tree)
    assert_not @tree.respond_to?(:elaborate_root)
  end

  test "assign_id sets uid to a fresh value not yet used" do
    fresh = Tree.new
    fresh.assign_id
    assert_kind_of String, fresh.uid
    assert fresh.uid.present?
    assert_nil Tree.find_by_uid(fresh.uid)
  end

  test "class_def_name delegates to the class_def" do
    assert_equal @class_def.name, @tree.class_def_name
  end
end
