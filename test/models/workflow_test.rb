require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  setup do
    @workflow = workflows(:orderly)
    @on_the_fly = workflows(:on_the_fly)
    @task = tasks(:alpha_task_one)
    @user = users(:alice)
    @task_user = task_users(:alice_admin_alpha_task_one)
    @kit = Kit.create!(task: @task, kit_type: kit_types(:basic), state: "assigned", uid: "wf-kit-#{SecureRandom.hex(3)}")
  end

  test "name uniqueness is enforced at the database level (no model validation)" do
    # The model has no `validates :name, uniqueness: true` — uniqueness is enforced only by
    # the unique index on workflows.name. A duplicate save raises ActiveRecord::RecordNotUnique.
    dup = Workflow.new(name: @workflow.name)
    assert dup.valid?, "no model-level validation, so the new record passes valid?"
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save! }
  end

  test "has_many tasks" do
    assert_includes @workflow.tasks, @task
  end

  test "sorted scope orders alphabetically by name" do
    names = Workflow.sorted.where(id: [@workflow.id, @on_the_fly.id]).pluck(:name)
    assert_equal names.sort, names
  end

  test "all_newest_first orders by created_at DESC" do
    rows = Workflow.all_newest_first.where(id: [@workflow.id, @on_the_fly.id]).to_a
    assert_operator rows.first.created_at, :>=, rows.last.created_at
  end

  test "new_kits_available? returns true for the OnTheFly workflow" do
    assert @on_the_fly.new_kits_available?(@task_user)
  end

  test "new_kits_available? returns false for non-OnTheFly workflows" do
    assert_not @workflow.new_kits_available?(@task_user)
  end

  # ── work_ajax message handling ──────────────────────────────────────────

  test "work_ajax 'skip' sets kit state to 'skip' and task_user back to needs_kit" do
    result = @workflow.work_ajax(@task_user, @kit, "skip", nil)
    assert_equal :work, result
    assert_equal "skip", @kit.reload.state
    assert_equal "needs_kit", @task_user.reload.state
  end

  test "work_ajax 'done' marks the kit done with the supplied comment" do
    result = @workflow.work_ajax(@task_user, @kit, "done", "looks good")
    assert_equal :work, result
    @kit.reload
    assert_equal "done", @kit.state
    assert_equal "looks good", @kit.done_comment
    assert_equal "needs_kit", @task_user.reload.state
  end

  test "work_ajax 'broken' marks the kit broken with the supplied comment" do
    result = @workflow.work_ajax(@task_user, @kit, "broken", "audio glitch")
    assert_equal :work, result
    @kit.reload
    assert_equal "broken", @kit.state
    assert_equal "audio glitch", @kit.broken_comment
  end

  test "work_ajax 'logout' pauses the task_user and returns :logout" do
    result = @workflow.work_ajax(@task_user, @kit, "logout", nil)
    assert_equal :logout, result
    assert_equal "paused", @task_user.reload.state
  end

  test "work_ajax 'switch' pauses the task_user and returns :home" do
    result = @workflow.work_ajax(@task_user, @kit, "switch", nil)
    assert_equal :home, result
    assert_equal "paused", @task_user.reload.state
  end

  test "work_ajax 'done_logout' marks kit done and returns :logout" do
    result = @workflow.work_ajax(@task_user, @kit, "done_logout", nil)
    assert_equal :logout, result
    assert_equal "done", @kit.reload.state
    assert_equal "needs_kit", @task_user.reload.state
  end

  test "work_ajax 'done_hold' marks kit done and parks task_user on hold" do
    result = @workflow.work_ajax(@task_user, @kit, "done_hold", nil)
    assert_equal :home, result
    assert_equal "done", @kit.reload.state
    assert_equal "hold", @task_user.reload.state
  end

  test "work_ajax with an unknown message returns nil" do
    assert_nil @workflow.work_ajax(@task_user, @kit, "totally-not-a-message", nil)
  end

  # ── lock_task / unlock_task ─────────────────────────────────────────────

  test "lock_task sets the task's lock_user_id to the current user; unlock_task clears it" do
    @workflow.instance_variable_set(:@task_id, @task.id)
    @workflow.instance_variable_set(:@user_id, @user.id)

    @workflow.lock_task
    assert_equal @user.id, @task.reload.lock_user_id

    @workflow.unlock_task
    assert_nil @task.reload.lock_user_id
  end

  test "lock_task raises TaskLockError if the task is already locked" do
    @task.update!(lock_user_id: users(:bob).id)
    @workflow.instance_variable_set(:@task_id, @task.id)
    @workflow.instance_variable_set(:@user_id, @user.id)

    assert_raises(Workflow::TaskLockError) { @workflow.lock_task }
    assert_equal users(:bob).id, @task.reload.lock_user_id
  end
end
