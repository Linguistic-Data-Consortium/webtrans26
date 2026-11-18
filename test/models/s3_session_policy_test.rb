require "test_helper"

# Who may read and write which project's S3 prefix, and the session policy
# that says so — aws/s3_project_prefixes.md. All data; nothing here reaches AWS.
#
#   alice  owner of alpha, member of beta, member (admin) of alpha_task_one
#   bob    member of alpha and of alpha_task_one
#   charlie in no project
class S3SessionPolicyTest < ActiveSupport::TestCase
  setup do
    @alpha = projects(:alpha)
    @beta = projects(:beta)
    @alice = users(:alice)
    @bob = users(:bob)
    @charlie = users(:charlie)
  end

  # ── who may read ───────────────────────────────────────────────────────────

  test "reading follows project membership" do
    assert_equal [ @alpha.id, @beta.id ].sort, @alice.s3_read_project_ids
    assert_equal [ @alpha.id ], @bob.s3_read_project_ids
    assert_equal [], @charlie.s3_read_project_ids
  end

  # ── who may write ──────────────────────────────────────────────────────────

  test "a project with no upload task is writable by nobody, its owner included" do
    assert_nil @alpha.s3_upload_task
    assert_not project_users(:alice_owns_alpha).may_write_s3?
    assert_equal [], @alice.s3_write_project_ids
  end

  test "writing is membership of the project's upload task, not a role" do
    @alpha.update!(s3_upload_task: tasks(:alpha_task_one))

    assert project_users(:bob_on_alpha).may_write_s3?, "bob is an ordinary member of the upload task"
    assert_equal [ @alpha.id ], @bob.s3_write_project_ids
    assert_equal [ @alpha.id ], @alice.s3_write_project_ids, "alice writes alpha but not beta"
  end

  test "owning the project is not enough without the upload task" do
    @alpha.update!(s3_upload_task: tasks(:alpha_task_two))

    assert_not project_users(:alice_owns_alpha).may_write_s3?
    assert_equal [], @alice.s3_write_project_ids
  end

  test "upload-task membership without project membership grants nothing" do
    @alpha.update!(s3_upload_task: tasks(:alpha_task_one))
    tasks(:alpha_task_one).users << @charlie

    assert_equal [], @charlie.s3_read_project_ids
    assert_equal [], @charlie.s3_write_project_ids
  end

  test "an upload task must belong to the project" do
    @alpha.s3_upload_task = tasks(:beta_task_one)

    assert_not @alpha.valid?
    assert_includes @alpha.errors[:s3_upload_task], "must be a task in this project"
  end

  test "deleting the upload task revokes write access and keeps the project" do
    task = Task.create!(name: "uploads-#{SecureRandom.hex(3)}", project: @alpha,
                        workflow: workflows(:orderly), kit_type: kit_types(:basic))
    @alpha.update!(s3_upload_task: task)
    task.destroy!

    assert_nil @alpha.reload.s3_upload_task_id
  end

  # ── the document ───────────────────────────────────────────────────────────

  test "read on every project, write on the writable subset, list by prefix" do
    @alpha.update!(s3_upload_task: tasks(:alpha_task_one))
    a = @alpha.id
    lo, hi = [ @alpha.id, @beta.id ].sort
    doc = S3SessionPolicy.new(@alice, bucket: "BUCKET").to_h

    assert_equal(
      { Version: "2012-10-17", Statement: [
        { Sid: "Read", Effect: "Allow", Action: [ "s3:GetObject" ],
          Resource: [ "arn:aws:s3:::BUCKET/#{lo}/*", "arn:aws:s3:::BUCKET/#{hi}/*" ] },
        { Sid: "Write", Effect: "Allow", Action: [ "s3:PutObject" ],
          Resource: [ "arn:aws:s3:::BUCKET/#{a}/*" ] },
        { Sid: "List", Effect: "Allow", Action: [ "s3:ListBucket" ],
          Resource: "arn:aws:s3:::BUCKET",
          Condition: { StringLike: { "s3:prefix" => [ "#{lo}/*", "#{hi}/*" ] } } }
      ] },
      doc
    )
  end

  test "with nothing writable there is no write statement, rather than an empty one" do
    sids = S3SessionPolicy.new(@alice, bucket: "BUCKET").to_h[:Statement].map { |s| s[:Sid] }

    assert_equal %w[Read List], sids
  end

  test "nothing grants delete" do
    @alpha.update!(s3_upload_task: tasks(:alpha_task_one))
    actions = S3SessionPolicy.new(@alice, bucket: "BUCKET").to_h[:Statement].flat_map { |s| s[:Action] }

    assert_equal %w[s3:GetObject s3:PutObject s3:ListBucket], actions
  end

  test "a user in no project has an empty policy" do
    assert S3SessionPolicy.new(@charlie, bucket: "BUCKET").empty?
  end

  test "ids are cast before they reach an ARN" do
    user = Struct.new(:s3_read_project_ids, :s3_write_project_ids).new([ "3/../*" ], [])

    assert_raises(ArgumentError) { S3SessionPolicy.new(user, bucket: "BUCKET") }
  end

  test "to_json is the document" do
    policy = S3SessionPolicy.new(@bob, bucket: "BUCKET")

    assert_equal JSON.parse(policy.to_h.to_json), JSON.parse(policy.to_json)
  end
end
