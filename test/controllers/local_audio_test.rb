require "test_helper"

# A kit type carrying local_audio, on an OnTheFly task, transcribes a file on
# the annotator's own computer. The work page can't make the kit on arrival —
# it would be named after a file only the browser can see — so it renders
# without one, and POST .../local_audio makes and assigns it once the file is
# picked. Only the name and size arrive; that's all the server ever learns.
class LocalAudioTest < ActionDispatch::IntegrationTest
  include SignInHelpers

  setup do
    @bob = users(:bob)
    @workflow = workflows(:on_the_fly)
    class_def = ClassDef.where(name: "ArcTranscription").first_or_create!
    root = NodeClass.where(name: "ArcTranscription:Root").first_or_create!(class_def: class_def)
    @kit_type = KitType.create!(name: "local-#{SecureRandom.hex(3)}", node_class: root)
    @kit_type.update!(constraints: { "local_audio" => "local_audio" })
    @task = Task.create!(name: "local-#{SecureRandom.hex(3)}", project: projects(:alpha),
                         workflow: @workflow, kit_type: @kit_type, status: "active")
    @task_user = TaskUser.create!(task: @task, user: @bob, state: "needs_kit")
    sign_in_as @bob
  end

  def work_path
    "/workflows/#{@task_user.id}/work/#{@workflow.id}"
  end

  test "the work page asks for the file instead of making a kit" do
    assert_no_difference -> { Kit.where(task_id: @task.id).count } do
      get work_path
    end
    assert_response :success
    assert_includes @response.body, "#{work_path}/local_audio"
    assert_equal "needs_kit", @task_user.reload.state
  end

  test "posting the file's name makes and assigns a kit named after it" do
    get work_path
    post "#{work_path}/local_audio", params: { name: "interview 3.wav", size: 123456 }, as: :json
    assert_response :success

    kit = Kit.where(task_id: @task.id).sole
    assert_equal "local://interview 3.wav", kit.source_uid
    assert_equal 123456, kit.source[:size]
    assert_equal "assigned", kit.state
    assert_equal @bob.id, kit.user_id
    assert_not_nil kit.tree_id
    @task_user.reload
    assert_equal "has_kit", @task_user.state
    assert_equal kit.uid, @task_user.kit_oid

    body = JSON.parse(@response.body)
    assert_equal kit.uid, body["initt"]["_id"]
    assert_equal "local://interview 3.wav", body["initt"]["source"]["uid"]
    assert_equal 123456, body["initt"]["source"]["size"]
    assert_equal({ "local://interview 3.wav" => "local://interview 3.wav" }, body["manifest"]["urls"])
    assert_equal({ "local_audio" => "local_audio" }, body["constraints"])
  end

  test "coming back to the kit renders it, with the size to check the re-pick against" do
    post "#{work_path}/local_audio", params: { name: "a.wav", size: 99 }, as: :json
    assert_no_difference -> { Kit.count } do
      get work_path
    end
    assert_response :success
    assert_includes @response.body, '"uid":"local://a.wav"'
    assert_includes @response.body, '"size":99'
    assert_not_includes @response.body, "local_audio_url"
  end

  test "a second post while holding a kit makes no second kit" do
    post "#{work_path}/local_audio", params: { name: "a.wav", size: 1 }, as: :json
    assert_no_difference -> { Kit.count } do
      post "#{work_path}/local_audio", params: { name: "b.wav", size: 1 }, as: :json
    end
    assert_response :conflict
    assert JSON.parse(@response.body)["reload"]
  end

  test "a name with a slash in it is refused" do
    assert_no_difference -> { Kit.count } do
      post "#{work_path}/local_audio", params: { name: "../x.wav", size: 1 }, as: :json
    end
    assert_response :unprocessable_entity
  end

  test "another user's task_user is refused" do
    delete session_url
    sign_in_as users(:alice)
    assert_no_difference -> { Kit.count } do
      post "#{work_path}/local_audio", params: { name: "a.wav", size: 1 }, as: :json
    end
    assert_response :forbidden
  end

  test "a task without the constraint takes no local audio" do
    @kit_type.update!(constraints: {})
    post "#{work_path}/local_audio", params: { name: "a.wav", size: 1 }, as: :json
    assert_response :unprocessable_entity
  end

  test "the constraint on a workflow other than OnTheFly is refused, not ignored" do
    @task.update!(workflow: workflows(:orderly))
    assert_no_difference -> { Kit.count } do
      get "/workflows/#{@task_user.id}/work/#{workflows(:orderly).id}"
    end
    assert_redirected_to user_path(@bob)
    assert_match(/OnTheFly/, flash[:info])
  end

  test "an OnTheFly task without the constraint still makes its kit on arrival" do
    @kit_type.update!(constraints: {})
    @task.update!(meta: { "docid" => "s3://bucket/x.wav" })
    assert_difference -> { Kit.where(task_id: @task.id).count }, 1 do
      get work_path
    end
    assert_equal "s3://bucket/x.wav", Kit.where(task_id: @task.id).sole.source_uid
  end
end
