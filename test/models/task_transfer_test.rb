require "test_helper"

# Copying a task out of one database and into another — what `bin/rails
# task:pull` does between production and development. Here both ends are this
# one database: the task is exported, removed, and loaded back, which is the
# check that the dump holds everything the task needs to exist.
class TaskTransferTest < ActiveSupport::TestCase
  setup do
    Annotation.where(id: 0).first_or_create
    @alice = users(:alice)
    @bob = users(:bob)
    @alpha = projects(:alpha)
    @task = tasks(:alpha_task_one)
    @class_def = ClassDef.where(name: "ArcTranscription").first_or_create!
    root = NodeClass.where(name: "ArcTranscription:Root").first_or_create!(class_def: @class_def)
    @kit_type = KitType.create!(name: "transfer-#{SecureRandom.hex(3)}", node_class: root)
    @task.update!(kit_type: @kit_type, meta: { "notes" => "a task with meta on it" })

    @tree = Tree.create!(uid: "transfer-#{SecureRandom.hex(4)}", class_def: @class_def, version: 2)
    annotate("add", value: "10:NListItem,11:N")
    annotate("change", iid: 11, docid: "a.wav", begr: 1.25)
    annotate("add", value: "12:NListItem,13:N")
    annotate("change", iid: 13, docid: "a.wav", begr: 3.5)
    annotate("add", value: "14:SegmentListItem,15:Arc,16:Text,17:Speaker")
    annotate("change", iid: 15, begi: 10, endi: 12)
    annotate("change", iid: 16, value: "a line")
    annotate("change", iid: 17, value: "alice")

    @kit = Kit.create!(
      task_id: @task.id, kit_type_id: @kit_type.id, tree_id: @tree.id,
      user_id: @alice.id, state: "assigned", source_uid: "a.wav",
      uid: "transfer-kit-#{SecureRandom.hex(4)}"
    )
  end

  def annotate(message, **attributes)
    Annotation.create!(
      { tree_id: @tree.id, task_id: @task.id, user_id: @alice.id, message: message, last_iid: "0" }
        .merge(attributes)
    )
  end

  def round_trip(replace: false)
    dump = TaskTransfer.export(@task.id)
    TaskTransfer.remove(@task.id)
    TaskTransfer.import(dump, replace: replace)
    dump
  end

  # ── what comes across ─────────────────────────────────────────────────────

  test "the task comes back with its own attributes" do
    round_trip
    task = Task.find(@task.id)
    assert_equal @task.name, task.name
    assert_equal @alpha.id, task.project_id
    assert_equal @kit_type.id, task.kit_type_id
  end

  test "a serialized column survives the trip unchanged" do
    # Task#meta is a Ruby-serialized hash. Copying rows through the models would
    # re-encode it; this copies the raw column, so what comes back is what went.
    before = Task.find(@task.id).read_attribute_before_type_cast("meta")
    round_trip
    assert_equal before, Task.find(@task.id).read_attribute_before_type_cast("meta")
    assert_equal "a task with meta on it", Task.find(@task.id).meta["notes"]
  end

  test "the kits and their trees come back, ids and all" do
    round_trip
    kit = Kit.find(@kit.id)
    assert_equal @kit.uid, kit.uid
    assert_equal @tree.id, kit.tree_id
    assert_equal "a.wav", kit.source_uid
    assert_equal @class_def.id, Tree.find(@tree.id).class_def_id
  end

  test "every annotation comes back, in order and with its values" do
    # The annotations are the record; a copy without them is not the task.
    before = Annotation.where(tree_id: @tree.id).order(:id).pluck(:id, :message, :iid, :value, :begr, :docid)
    round_trip
    assert_equal before,
                 Annotation.where(tree_id: @tree.id).order(:id).pluck(:id, :message, :iid, :value, :begr, :docid)
  end

  test "the copy replays into the same graph the original did" do
    # The real test of a faithful copy: what the tool draws is replayed from the
    # log, so the replay has to come out the same.
    before = Kit.find(@kit.id).graph_projection
    round_trip
    assert_equal before, Kit.find(@kit.id).graph_projection
    assert_equal [ 1.25, 3.5 ], Kit.find(@kit.id).graph_projection[:nodes].map { |n| n[:time] }
  end

  test "the task's members come back" do
    round_trip
    assert_equal [ @alice.id, @bob.id ].sort, TaskUser.where(task_id: @task.id).pluck(:user_id).sort
    assert TaskUser.find_by(task_id: @task.id, user_id: @alice.id).admin
  end

  test "the kit type, its node class and the class def behind it all come" do
    dump = TaskTransfer.export(@task.id)
    names = ->(table) { dump["tables"][table]["rows"].length }
    assert_equal 1, names.call("kit_types")
    assert_operator names.call("node_classes"), :>=, 1
    assert_operator names.call("class_defs"), :>=, 1
  end

  test "projections are left out — they rebuild from the log" do
    dump = TaskTransfer.export(@task.id)
    assert_not dump["tables"].key?("graph_nodes")
    assert_not dump["tables"].key?("segments")
  end

  test "the dump says what it is and where it came from" do
    dump = TaskTransfer.export(@task.id)
    assert_equal TaskTransfer::FORMAT, dump["format"]
    assert_equal @task.id, dump["task_id"]
    assert_equal @task.name, dump["task_name"]
    assert_equal "test", dump["exported_from"]
    assert_match(/\A\d+\z/, dump["schema_version"])
  end

  # ── users ─────────────────────────────────────────────────────────────────

  test "a user already here by email keeps their own row and their id" do
    round_trip
    assert_equal @alice.id, Kit.find(@kit.id).user_id
    assert_equal 1, User.where(email_address: @alice.email_address).count
  end

  test "a user not here arrives with their name and no way in" do
    # Their password doesn't come with them: a real digest in a development
    # database is a credential nobody meant to copy.
    dump = TaskTransfer.export(@task.id)
    TaskTransfer.remove(@task.id)
    @alice.destroy!
    TaskTransfer.import(dump)

    arrived = User.find_by(email_address: users(:alice).email_address)
    assert_not_nil arrived
    assert_equal "alice", arrived.name
    assert_not arrived.admin
    assert_not arrived.activated
    assert_not arrived.authenticate("password123")
  end

  test "references follow a user to whatever id they have here" do
    dump = TaskTransfer.export(@task.id)
    was = @alice.id
    TaskTransfer.remove(@task.id)
    @alice.destroy!
    # A different user takes the id the dump's rows point at, so a copy that
    # ignored the mapping would hand this task's kits to the wrong person.
    squatter = User.create!(id: was, email_address: "squatter@example.com", name: "squatter",
                            password: "password123", password_confirmation: "password123")
    TaskTransfer.import(dump)

    alice = User.find_by!(email_address: users(:alice).email_address)
    assert_not_equal squatter.id, alice.id
    assert_equal alice.id, Kit.find(@kit.id).user_id
    assert_equal alice.id, Annotation.where(tree_id: @tree.id).first.user_id
  end

  # ── what it refuses ───────────────────────────────────────────────────────

  test "it refuses to import over a task that is already here" do
    dump = TaskTransfer.export(@task.id)
    error = assert_raises(TaskTransfer::Refused) { TaskTransfer.import(dump) }
    assert_match(/already in test/, error.message)
    assert_match(/1 kits/, error.message)
    assert_match(/1 annotations|\d+ annotations/, error.message)
  end

  test "…and leaves what is here alone when it does" do
    dump = TaskTransfer.export(@task.id)
    assert_no_difference [ -> { Kit.count }, -> { Annotation.count } ] do
      assert_raises(TaskTransfer::Refused) { TaskTransfer.import(dump) }
    end
  end

  test "replace overwrites it instead" do
    dump = TaskTransfer.export(@task.id)
    assert_no_difference [ -> { Kit.count }, -> { Annotation.count }, -> { Task.count } ] do
      TaskTransfer.import(dump, replace: true)
    end
    assert_equal "a line", Annotation.where(tree_id: @tree.id, iid: 16).first.value
  end

  test "replace leaves other tasks' kits where they are" do
    other_task = Task.create!(name: "other-#{SecureRandom.hex(3)}", project: @alpha,
                              workflow: @task.workflow, kit_type: @kit_type)
    other_kit = Kit.create!(task_id: other_task.id, kit_type_id: @kit_type.id,
                            uid: "other-#{SecureRandom.hex(4)}", state: "unassigned")

    TaskTransfer.import(TaskTransfer.export(@task.id), replace: true)
    assert Kit.exists?(other_kit.id)
    assert Task.exists?(other_task.id)
  end

  test "it refuses a dump it doesn't understand" do
    dump = TaskTransfer.export(@task.id).merge("format" => 99)
    error = assert_raises(TaskTransfer::Refused) { TaskTransfer.import(dump) }
    assert_match(/unknown dump format/, error.message)
  end

  test "it refuses a dump with a column this database hasn't got" do
    # Schema drift between production and here. Loading the rest and guessing at
    # the gap would be worse than stopping.
    dump = TaskTransfer.export(@task.id)
    dump["tables"]["kits"]["columns"] += [ "invented_later" ]
    dump["tables"]["kits"]["rows"].each { |row| row << "x" }

    error = assert_raises(TaskTransfer::Refused) { TaskTransfer.import(dump) }
    assert_match(/invented_later/, error.message)
  end

  test "a column added since the dump is fine — it takes its default" do
    dump = TaskTransfer.export(@task.id)
    at = dump["tables"]["kits"]["columns"].index("done_comment")
    dump["tables"]["kits"]["columns"].delete_at(at)
    dump["tables"]["kits"]["rows"].each { |row| row.delete_at(at) }

    TaskTransfer.remove(@task.id)
    TaskTransfer.import(dump)
    assert_nil Kit.find(@kit.id).done_comment
  end

  test "exporting a task that isn't there says so" do
    error = assert_raises(TaskTransfer::Refused) { TaskTransfer.export(-1) }
    assert_match(/no task #-1/, error.message)
  end

  # ── remove ────────────────────────────────────────────────────────────────

  test "removing takes the task's own rows and nothing shared" do
    TaskTransfer.remove(@task.id)

    assert_not Task.exists?(@task.id)
    assert_not Kit.exists?(@kit.id)
    assert_not Tree.exists?(@tree.id)
    assert_empty Annotation.where(tree_id: @tree.id)
    # Shared rows stay: another task may be sitting on any of them.
    assert Project.exists?(@alpha.id)
    assert KitType.exists?(@kit_type.id)
    assert ClassDef.exists?(@class_def.id)
    assert User.exists?(@alice.id)
  end

  test "removing takes the projections with it, since nothing rebuilds them" do
    Kit.find(@kit.id).graph_snapshot
    assert GraphArc.by_tree(@tree.id).any?

    TaskTransfer.remove(@task.id)
    assert_empty GraphArc.by_tree(@tree.id)
    assert_empty GraphNode.by_tree(@tree.id)
  end
end
