require "test_helper"

# The manifest tells the tool where a kit's audio is. When the kit names its
# source directly — no Source row — that name is what the client resolves: an
# s3:// url it signs, an http url or a path it uses as it stands.
#
# It used to build "s3" and append a bucket read off the task's data set. The
# data_sets table is gone, so every kit whose source_uid wasn't already an
# s3:// url got the bare string "s3" and the tool alerted "missing bucket".
class KitSourceManifestTest < ActiveSupport::TestCase
  setup do
    @task = tasks(:alpha_task_one)
    @workflow = @task.workflow
  end

  def manifest_for(source_uid)
    kit = Kit.create!(
      task_id: @task.id, kit_type_id: @task.kit_type_id, state: "unassigned",
      uid: "manifest-#{SecureRandom.hex(3)}", source_uid: source_uid,
      source: { uid: source_uid, id: source_uid, filename: source_uid }
    )
    controller = TaskUsersController.new
    controller.instance_variable_set(:@kit, kit)
    controller.instance_variable_set(:@task, @task)
    controller.instance_variable_set(:@workflow, @workflow)
    controller.send(:kit_source_helper)
    controller.instance_variable_get(:@manifest)
  end

  test "an s3 url is handed over as it stands, for the client to sign" do
    uid = "s3://my-bucket/recordings/REC_passage_reading.wav"

    assert_equal({ urls: { uid => uid } }, manifest_for(uid))
  end

  test "a docid with no scheme is handed over as it stands, not turned into 's3'" do
    uid = "REC_passage_reading.wav"

    assert_equal({ urls: { uid => uid } }, manifest_for(uid))
  end

  test "a path is handed over as it stands" do
    assert_equal({ urls: { "/test_tone_10s.wav" => "/test_tone_10s.wav" } },
                 manifest_for("/test_tone_10s.wav"))
  end

  test "an http url is handed over as it stands" do
    uid = "https://example.org/audio/REC.wav"

    assert_equal({ urls: { uid => uid } }, manifest_for(uid))
  end

  # The task's data set is what used to supply the bucket. There is no
  # data_sets table any more, so reading one would raise rather than return an
  # empty bucket.
  test "nothing reads the task's data set on the way through" do
    assert_nil @task.data_set_id
    assert_nothing_raised { manifest_for("REC_passage_reading.wav") }
    assert_not @workflow.respond_to?(:bucket_name),
      "Workflow#bucket_name read the data set too, and nothing called it"
  end
end
