require "test_helper"

# Download features are admins' alone unless a project names a download task,
# whose members then have them for that project (Project#may_download?).
#
#   alice  owner of alpha, admin of alpha_task_one — but not a system admin
#   bob    member of alpha_task_one
class DownloadPermissionTest < ActionDispatch::IntegrationTest
  setup do
    @alpha = projects(:alpha)
    @task = tasks(:alpha_task_one)
  end

  def may_download_on_task_view(user)
    sign_in_as user
    get task_url(@task), as: :json
    JSON.parse(@response.body)["may_download"]
  end

  test "by default only a system admin may download — not owners or task admins" do
    assert_nil @alpha.download_task
    assert @alpha.may_download?(users(:admin))
    assert_not @alpha.may_download?(users(:alice)), "project owner and task admin"
    assert_not @alpha.may_download?(users(:pat)), "portal manager"
    assert_equal false, may_download_on_task_view(users(:alice))
  end

  test "members of the download task may, for that project only" do
    @alpha.update!(download_task: @task)
    assert @alpha.may_download?(users(:bob))
    assert_equal true, may_download_on_task_view(users(:alice))
    assert_not projects(:beta).may_download?(users(:bob))
  end

  test "a task from another project can't be the download task" do
    @alpha.download_task = tasks(:beta_task_one)
    assert_not @alpha.valid?
    assert_includes @alpha.errors[:download_task], "must be a task in this project"
  end

  test "the owner sets the download task, and it's in the security log" do
    sign_in_as users(:alice)
    patch project_url(@alpha), params: { project: { download_task_id: @task.id } }, as: :json
    assert_equal @task, @alpha.reload.download_task
    e = SecurityEvent.where(event: "download_task.changed").last
    assert_equal [ users(:alice).id, "alpha_task_one" ], [ e.actor_id, e.details["task"] ]

    patch project_url(@alpha), params: { project: { download_task_id: nil } }, as: :json
    assert_nil @alpha.reload.download_task
  end

  test "someone who isn't the owner can't set it" do
    sign_in_as users(:bob)
    patch project_url(@alpha), params: { project: { download_task_id: @task.id } }, as: :json
    assert_nil @alpha.reload.download_task
  end

  test "deleting the download task takes the permission with it" do
    @alpha.update!(download_task: tasks(:alpha_task_two))
    tasks(:alpha_task_two).destroy
    assert_nil @alpha.reload.download_task_id
  end

  test "the project's task list says which task is the download task" do
    @alpha.update!(download_task: @task)
    sign_in_as users(:alice)
    get project_url(@alpha), as: :json
    body = JSON.parse(@response.body)
    assert_equal @task.id, body["download_task_id"]
    assert_equal "yes", body["tasks"].find { |t| t["id"] == @task.id }["download"]
  end

  # The editor's ⬇ button follows the page data's may_download.
  test "the editor is told whether this user may download" do
    kit = Kit.create!(task_id: @task.id, kit_type_id: @task.kit_type_id, state: "unassigned")
    sign_in_as users(:alice)
    get "/workflows/#{workflows(:orderly).id}/read_only/#{kit.uid}"
    assert_match(/"may_download":false/, response.body)

    @alpha.update!(download_task: @task)
    get "/workflows/#{workflows(:orderly).id}/read_only/#{kit.uid}"
    assert_match(/"may_download":true/, response.body)
  end
end

