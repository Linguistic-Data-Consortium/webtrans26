require "test_helper"

class KitTypeTest < ActiveSupport::TestCase
  test "composite_name returns 'id:name'" do
    kt = kit_types(:basic)
    assert_equal "#{kt.id}:#{kt.name}", kt.composite_name
  end

  test "has_many kits" do
    kt = kit_types(:basic)
    Kit.create!(task_id: tasks(:alpha_task_one).id, kit_type: kt, state: "unassigned", uid: "kt-test-#{SecureRandom.hex(3)}")
    assert_operator kt.kits.count, :>=, 1
  end

  test "sorted scope orders by created_at DESC" do
    older = kit_types(:basic)
    newer = KitType.create!(name: "newer-#{SecureRandom.hex(3)}", node_class: node_classes(:root))
    rows = KitType.sorted.where(id: [older.id, newer.id]).to_a
    assert_equal newer, rows.first
    assert_equal older, rows.last
  end

  test "node_class is required for new records" do
    kt = KitType.new(name: "no-node-class")
    assert_not kt.valid?
    assert kt.errors[:node_class].any?
  end

  test "constraints serializes to a Hash" do
    kt = KitType.create!(name: "with-constraints-#{SecureRandom.hex(3)}", node_class: node_classes(:root), constraints: { "free_choice" => "free_choice" })
    assert_equal "free_choice", kt.reload.constraints["free_choice"]
  end
end
