require "test_helper"

class KitTest < ActiveSupport::TestCase
  setup do
    @task = tasks(:alpha_task_one)
    @kit = Kit.create!(
      task_id: @task.id,
      kit_type_id: @task.kit_type_id,
      state: "unassigned",
      uid: "kit-test-#{SecureRandom.hex(3)}"
    )
  end

  # ── associations ─────────────────────────────────────────────────────────

  test "belongs_to task / kit_type / user (all optional)" do
    assert_equal @task, @kit.task
    assert_equal kit_types(:basic), @kit.kit_type
    assert_nil @kit.user
  end

  test "has_many kit_states / kit_stats / kit_values" do
    assert_respond_to @kit, :kit_states
    assert_respond_to @kit, :kit_stats
    assert_respond_to @kit, :kit_values
  end

  # ── scopes ───────────────────────────────────────────────────────────────

  test "unassigned_by_task returns only unassigned kits for that task" do
    assigned = Kit.create!(
      task_id: @task.id,
      kit_type_id: @task.kit_type_id,
      state: "assigned",
      uid: "kit-assigned-#{SecureRandom.hex(3)}"
    )
    rows = Kit.unassigned_by_task(@task.id)
    assert_includes rows, @kit
    assert_not_includes rows, assigned
  end

  test "assigned_by_task returns only assigned kits for that task" do
    assigned = Kit.create!(
      task_id: @task.id,
      kit_type_id: @task.kit_type_id,
      state: "assigned",
      uid: "kit-assigned-#{SecureRandom.hex(3)}"
    )
    rows = Kit.assigned_by_task(@task.id)
    assert_includes rows, assigned
    assert_not_includes rows, @kit
  end

  test "unassigned_by_task_and_user filters by both state and user_id" do
    other = Kit.create!(
      task_id: @task.id, kit_type_id: @task.kit_type_id,
      state: "unassigned", uid: "kit-other-#{SecureRandom.hex(3)}",
      user_id: users(:bob).id
    )
    rows = Kit.unassigned_by_task_and_user(@task.id, users(:bob).id)
    assert_includes rows, other
    assert_not_includes rows, @kit
  end

  # ── goto_state callback ─────────────────────────────────────────────────

  test "after save the first state change records a KitState transition" do
    # The very first save in setup creates the initial KitState (last is nil → branch records it).
    assert_equal 1, @kit.kit_states.count
    assert_equal "unassigned", @kit.kit_states.last.state
  end

  test "saving with a new state appends a KitState transition" do
    assert_difference -> { @kit.kit_states.count }, 1 do
      @kit.update!(state: "assigned")
    end
    assert_equal "assigned", @kit.kit_states.last.state
  end

  test "saving without a state change does not append a KitState row" do
    @kit.reload
    assert_no_difference -> { @kit.kit_states.count } do
      @kit.update!(uid: "kit-renamed-#{SecureRandom.hex(3)}")
    end
  end

  # ── assign_id / requeue ─────────────────────────────────────────────────

  test "assign_id returns a uid that is not currently used by another kit" do
    new_uid = @kit.assign_id
    assert_kind_of String, new_uid
    assert_nil Kit.find_by_uid(new_uid)
  end

  test "requeue regenerates the uid only when state is unassigned" do
    original_uid = @kit.uid
    @kit.requeue
    assert_not_equal original_uid, @kit.reload.uid
  end

  test "requeue is a no-op when kit is not unassigned" do
    @kit.update!(state: "assigned")
    original_uid = @kit.uid
    @kit.requeue
    assert_equal original_uid, @kit.reload.uid
  end

  # ── meta proxy methods (note the meta override is broken; pin observable behavior) ─────

  test "meta-proxy setters mutate the in-memory hash exposed by `meta`" do
    @kit.view = "open"
    assert_equal "open", @kit.view
    assert_equal "open", @kit.meta["view"]
  end

  test "meta accessor returns a Hash even on a fresh record" do
    fresh = Kit.new
    assert_kind_of Hash, fresh.meta
  end

  # ── snapshot ─────────────────────────────────────────────────────────────

  # Regression: a kit that has never been opened has tree_id nil, and snapshot
  # used to call tree.nodes on it — so KitsController#all (which snapshots every
  # kit in the task) 500'd as soon as one unopened kit existed.
  test "snapshot is a no-op for a kit with no tree" do
    assert_nil @kit.tree_id
    assert_nothing_raised { @kit.snapshot }
  end
end
