require "test_helper"

class KitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @alice = users(:alice)
    @task = tasks(:alpha_task_one)
    @class_def = ClassDef.create!(name: "TestCD-#{SecureRandom.hex(3)}")
    @kit = Kit.create!(
      task_id: @task.id,
      kit_type_id: @task.kit_type_id,
      state: "unassigned",
      uid: "unit-kit-#{SecureRandom.hex(3)}"
    )
  end

  def make_tree
    Tree.create!(uid: "tree-#{SecureRandom.hex(3)}", class_def: @class_def)
  end

  # ── all (transcript download source) ─────────────────────────────────────

  # Regression: #all snapshots every kit in the task, and Kit#snapshot used to
  # assume a tree. One never-opened kit (tree_id nil) took the whole endpoint
  # down with "undefined method 'nodes' for nil".
  test "all succeeds when the task has a kit that was never opened" do
    sign_in_as @admin
    assert_nil @kit.tree_id
    get "/kits/all", params: { task_id: @task.id }, as: :json
    assert_response :success
    assert_kind_of Array, JSON.parse(@response.body)
  end

  # ── change_kit_state ─────────────────────────────────────────────────────

  test "change_kit_state updates the kit's state for a lead annotator" do
    sign_in_as @admin
    patch change_kit_state_kits_path, params: { kit: { uid: @kit.uid, state: "done" } }
    assert_response :redirect # the action `redirect_back fallback_location: root_path`
    assert_equal "done", @kit.reload.state
  end

  test "change_kit_state with 'broken' sets the kit to broken" do
    # NOTE: the controller also sets `@kit.meta['broken_comment']`, but Kit.rb overrides
    # `meta` with a plain `@meta ||= {}` getter that bypasses the serialized column, so the
    # comment mutation is never persisted. We just assert the state change here.
    sign_in_as @admin
    patch change_kit_state_kits_path, params: { kit: { uid: @kit.uid, state: "broken" } }
    assert_equal "broken", @kit.reload.state
  end

  test "change_kit_state returning an 'assigned' kit to unassigned resets its task_user" do
    # Reuse the fixture task_user (alice on alpha_task_one) — the (task_id,user_id) pair is unique.
    tu = task_users(:alice_admin_alpha_task_one)
    tu.update!(state: "has_kit", kit_oid: @kit.uid)
    @kit.update!(state: "assigned", user_id: @alice.id)

    sign_in_as @admin
    patch change_kit_state_kits_path, params: { kit: { uid: @kit.uid, state: "unassigned" } }

    assert_equal "unassigned", @kit.reload.state
    tu.reload
    assert_nil tu.kit_oid
    assert_equal "needs_kit", tu.state
  end

  test "change_kit_state redirects non-lead-annotators back to root" do
    sign_in_as @alice
    patch change_kit_state_kits_path, params: { kit: { uid: @kit.uid, state: "done" } }
    assert_redirected_to root_path
    assert_equal "unassigned", @kit.reload.state # unchanged
  end

  # ── unlock_tree ──────────────────────────────────────────────────────────

  test "unlock_tree clears the tree lock when the caller holds it" do
    tree = make_tree
    tree.update!(locked: @alice.id)
    @kit.update!(tree_id: tree.id)

    sign_in_as @alice
    get unlock_tree_kits_path(id: @kit.id), as: :json

    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "success", body["done"]
    assert_nil tree.reload.locked
  end

  test "unlock_tree allows an admin to clear any user's lock" do
    tree = make_tree
    tree.update!(locked: @alice.id)
    @kit.update!(tree_id: tree.id)

    sign_in_as @admin
    get unlock_tree_kits_path(id: @kit.id), as: :json

    assert_response :success
    assert_equal "success", JSON.parse(@response.body)["done"]
    assert_nil tree.reload.locked
  end

  test "unlock_tree refuses when the caller is not the lock holder nor admin" do
    tree = make_tree
    tree.update!(locked: @admin.id)
    @kit.update!(tree_id: tree.id)

    sign_in_as @alice
    get "/kits/#{@kit.id}/unlock_tree", as: :json

    assert_response :success
    assert_equal "failure", JSON.parse(@response.body)["done"]
    assert_equal @admin.id, tree.reload.locked
  end

  # ── undo ─────────────────────────────────────────────────────────────────

  test "undo returns the kit's annotation history as JSON (empty for a fresh kit)" do
    sign_in_as @admin
    get "/kits/#{@kit.id}/undo", as: :json
    assert_response :success
    body = JSON.parse(@response.body)
    assert_kind_of Array, body
    assert_equal [], body
  end

  # ── get_time_spent / change_time_spent ───────────────────────────────────

  test "get_time_spent returns the kit's current time_spent" do
    @kit.update!(time_spent: 42)
    sign_in_as @alice
    get get_time_spent_kits_path(uid: @kit.uid), as: :json
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "success", body["type"]
    assert_equal "42", body["message"]
  end

  test "change_time_spent sets the kit's time_spent" do
    sign_in_as @alice
    post change_time_spent_kits_path, params: { uid: @kit.uid, time_spent: 99 }, as: :json
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "success", body["type"]
    assert_equal 99, @kit.reload.time_spent
  end

  test "time_spent endpoints require authentication" do
    get get_time_spent_kits_path(uid: @kit.uid), as: :json
    assert_redirected_to new_session_path

    post change_time_spent_kits_path, params: { uid: @kit.uid, time_spent: 1 }, as: :json
    assert_redirected_to new_session_path
  end

  # ── set_kits_done (admin-only) ───────────────────────────────────────────

  test "set_kits_done flips all unassigned kits on a task to done" do
    Kit.create!(task_id: @task.id, kit_type_id: @task.kit_type_id, state: "unassigned", uid: "todo-1-#{SecureRandom.hex(2)}")
    Kit.create!(task_id: @task.id, kit_type_id: @task.kit_type_id, state: "unassigned", uid: "todo-2-#{SecureRandom.hex(2)}")
    assigned = Kit.create!(task_id: @task.id, kit_type_id: @task.kit_type_id, state: "assigned", uid: "in-progress-#{SecureRandom.hex(2)}")

    sign_in_as @admin
    post set_kits_done_kits_path, params: { task: { id: @task.id } }
    assert_response :redirect

    # The 2 unassigned were flipped to done; the assigned one untouched.
    assert_equal "assigned", assigned.reload.state
    assert_equal 0, Kit.where(task_id: @task.id, state: "unassigned").count
  end

  test "set_kits_done is admin-only" do
    untouched = Kit.create!(task_id: @task.id, kit_type_id: @task.kit_type_id, state: "unassigned", uid: "guarded-#{SecureRandom.hex(2)}")
    sign_in_as @alice
    post set_kits_done_kits_path, params: { task: { id: @task.id } }
    assert_redirected_to root_path
    assert_equal "unassigned", untouched.reload.state
  end
end
