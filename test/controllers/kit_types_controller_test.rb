require "test_helper"

# Kit types belong to no project, so a project manager may change one only
# when they administer every task that uses it.
#
#   basic     used by alpha's tasks (alice owns alpha) and beta's (alice is
#             only a member there)
#   advanced  used by no task
class KitTypesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    GroupUser.create!(group: groups(:project_managers), user: @alice)
    @basic = kit_types(:basic)
    @advanced = kit_types(:advanced)
    # The fixtures have no node class, and a kit type needs one to save.
    root = NodeClass.create!(name: "KitTypeTest:Root")
    [ @basic, @advanced ].each { |kt| kt.update_columns(node_class_id: root.id) }
  end

  def rename(kit_type, name)
    patch kit_type_url(kit_type), params: { kit_type: { name: name } }, as: :json
    JSON.parse(@response.body)
  end

  test "a project manager can't rename a type that another project's task uses" do
    sign_in_as @alice
    body = rename(@basic, "renamed")
    assert_match(/tasks you don't administer/, body["error"])
    assert_equal "basic_kit_type", @basic.reload.name
  end

  test "a project manager can't delete a type that another project's task uses" do
    sign_in_as @alice
    delete kit_type_url(@basic), as: :json
    assert_match(/tasks you don't administer/, JSON.parse(@response.body)["error"])
    assert KitType.exists?(@basic.id)
  end

  test "kits count as use: a type reached only through a kit in another project is refused" do
    Kit.create!(task: tasks(:beta_task_one), kit_type: @advanced, state: "unassigned",
      uid: "kt-kit-#{SecureRandom.hex(3)}")
    sign_in_as @alice
    assert_match(/tasks you don't administer/, rename(@advanced, "renamed")["error"])
  end

  test "a project manager can change a type that only their own tasks use" do
    tasks(:alpha_task_two).update!(kit_type: @advanced)
    sign_in_as @alice
    body = rename(@advanced, "alpha_only")
    assert_nil body["error"]
    assert_equal "alpha_only", @advanced.reload.name
  end

  test "a project manager can change a type no task uses yet" do
    sign_in_as @alice
    assert_nil rename(@advanced, "fresh")["error"]
  end

  test "a portal manager can change any type" do
    sign_in_as users(:pat)
    assert_nil rename(@basic, "by_pat")["error"]
    assert_equal "by_pat", @basic.reload.name
  end
end
