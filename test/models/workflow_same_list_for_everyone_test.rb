require "test_helper"

# Every user of the task works the same list of documents, which the task
# carries as rows. The general form of WorkflowTemp, which had three docids
# written into the class.
class WorkflowSameListForEveryoneTest < ActiveSupport::TestCase
  DOCIDS = [ "s3://bucket/one.json", "s3://bucket/two.json", "s3://bucket/three.json" ].freeze

  setup do
    @workflow = Workflow.where(name: "SameListForEveryone").first_or_create!(
      user_states: "needs_kit,has_kit", description: "test"
    )
    Workflow.where(id: @workflow.id).update_all(type: "WorkflowSameListForEveryone")
    @workflow = Workflow.find(@workflow.id)
    @task = tasks(:alpha_task_one)
    @task.update!(workflow: @workflow)
    @alice = task_users(:alice_admin_alpha_task_one)
    @bob = task_users(:bob_on_alpha_task_one)
    TaskDocid.replace_for(@task.id, DOCIDS)
  end

  def kits_for(task_user)
    Kit.where(task_id: @task.id, user_id: task_user.user_id)
  end

  # The tool asks the workflow for work; this is the part that creates.
  def create_for(task_user)
    @workflow.instance_variable_set(:@task_user, task_user)
    @workflow.instance_variable_set(:@task_id, task_user.task_id)
    @workflow.instance_variable_set(:@user_id, task_user.user_id)
    @workflow.create_more_kits_if_necessary
  end

  test "it is loaded as its subclass, so #main is what runs" do
    assert_instance_of WorkflowSameListForEveryone, Workflow.find(@workflow.id)
  end

  # The dashboard asks this to decide between a Start Now link and "No
  # Available Kits", and asks it before any kit exists — which is the whole
  # difficulty: counting kit rows says "none" for everyone who hasn't started,
  # so the link they need in order to start never appears.
  test "there is work available before any kit exists" do
    assert_equal 0, Kit.where(task_id: @task.id).count

    assert @workflow.new_kits_available?(@alice)
    assert_equal 3, @workflow.kits_left(@alice)
  end

  test "there is no work left once the user has had the whole list" do
    create_for(@alice)
    kits_for(@alice).update_all(state: "done")

    assert_not @workflow.new_kits_available?(@alice)
    assert_equal 0, @workflow.kits_left(@alice)
  end

  # Once the kits exist there's nothing left to promise, and the dashboard has
  # kit rows of its own to count — which is the ordinary path every other
  # workflow takes.
  test "a user part-way through is accounted for by their kits" do
    create_for(@alice)
    kits_for(@alice).limit(2).update_all(state: "done")

    assert_not @workflow.new_kits_available?(@alice), "every document is on a kit of theirs now"
    assert_equal 1, kits_for(@alice).where(state: "unassigned").count,
      "and the one still waiting is what the dashboard counts instead"
  end

  test "an empty list is no work" do
    TaskDocid.replace_for(@task.id, [])

    assert_not @workflow.new_kits_available?(@bob)
    assert_equal 0, @workflow.kits_left(@bob)
  end

  test "one user's progress isn't another's" do
    create_for(@alice)

    assert_not @workflow.new_kits_available?(@alice)
    assert @workflow.new_kits_available?(@bob), "bob hasn't had any of them"
    assert_equal 3, @workflow.kits_left(@bob)
  end

  test "asking doesn't need the workflow to have been through #work" do
    fresh = Workflow.find(@workflow.id)

    assert_nil fresh.instance_variable_get(:@task_id)
    assert fresh.new_kits_available?(@alice), "reads the task and user from the argument"
  end

  # The Project Tasks table's "Available Kits" column. For a task nobody has
  # started that's the whole list, once per member, and no kits at all — where
  # counting unassigned kits would have said 0.
  test "outstanding work counts what every member is still owed" do
    assert_equal 0, Kit.where(task_id: @task.id).count

    # alice and bob are both members; three documents each.
    assert_equal 6, @workflow.outstanding_kit_count(@task, 0)
  end

  test "work already done doesn't count as outstanding" do
    create_for(@alice)
    kits_for(@alice).update_all(state: "done")

    # alice's three are accounted for; bob is still owed three.
    assert_equal 3, @workflow.outstanding_kit_count(@task, 0)
  end

  test "kits waiting to be picked up count too" do
    create_for(@alice)
    unassigned = kits_for(@alice).where(state: "unassigned").count
    assert_equal 3, unassigned

    # bob's three, plus alice's three sitting unassigned.
    assert_equal 6, @workflow.outstanding_kit_count(@task, unassigned)
  end

  test "a task with no list falls back to counting kits" do
    TaskDocid.replace_for(@task.id, [])

    assert_equal 4, @workflow.outstanding_kit_count(@task, 4)
  end

  test "a user with nothing to do is given the task's list" do
    create_for(@alice)

    assert_equal DOCIDS.sort, kits_for(@alice).pluck(:source_uid).sort
    assert_equal [ @alice.user_id ] * 3, kits_for(@alice).pluck(:user_id), "each kit is theirs"
    assert_equal [ "unassigned" ] * 3, kits_for(@alice).pluck(:state)
  end

  test "every user gets the same list, and their own kits" do
    create_for(@alice)
    create_for(@bob)

    assert_equal DOCIDS.sort, kits_for(@bob).pluck(:source_uid).sort
    assert_equal 6, Kit.where(task_id: @task.id).count, "three each, not three shared"
  end

  test "running again adds nothing — they've already been added" do
    create_for(@alice)

    assert_no_difference -> { Kit.count } do
      create_for(@alice)
      create_for(@alice)
    end
  end

  test "a user part-way through the list is left alone" do
    create_for(@alice)
    # One kit still waiting for them: they haven't run out, so nothing is due.
    kits_for(@alice).limit(2).update_all(state: "done")

    assert_no_difference -> { Kit.count } do
      create_for(@alice)
    end
  end

  test "a document added to the list later reaches a user who has finished" do
    create_for(@alice)
    kits_for(@alice).update_all(state: "done")
    TaskDocid.replace_for(@task.id, DOCIDS + [ "s3://bucket/four.json" ])

    create_for(@alice)

    assert_equal [ "s3://bucket/four.json" ], kits_for(@alice).where(state: "unassigned").pluck(:source_uid),
      "only the new one — the other three they've had"
  end

  test "a document removed from the list isn't given out again" do
    create_for(@alice)
    kits_for(@alice).update_all(state: "done")
    TaskDocid.replace_for(@task.id, DOCIDS.first(1))

    assert_no_difference -> { Kit.count } do
      create_for(@alice)
    end
  end

  test "an empty list creates nothing rather than failing" do
    TaskDocid.replace_for(@task.id, [])

    assert_no_difference -> { Kit.count } do
      create_for(@alice)
    end
  end

  test "another task's list is another task's business" do
    other = tasks(:alpha_task_two)
    TaskDocid.replace_for(other.id, [ "s3://bucket/elsewhere.json" ])

    create_for(@alice)

    assert_equal DOCIDS.sort, kits_for(@alice).pluck(:source_uid).sort
  end
end
