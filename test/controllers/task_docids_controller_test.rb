require "test_helper"

# The Docid List tab reads and writes through here: GET the list, POST the
# whole thing back as typed.
class TaskDocidsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @task = tasks(:alpha_task_one)
    @alice = users(:alice)   # task admin on alpha_task_one
    @bob = users(:bob)       # a member, not an admin
  end

  def get_list(task_id: @task.id)
    get "/task_docids", params: { task_id: task_id }, as: :json
    JSON.parse(@response.body)
  end

  def post_list(text, task_id: @task.id)
    post "/task_docids", params: { task_id: task_id, docids: text }, as: :json
    JSON.parse(@response.body)
  end

  test "an empty task has an empty list" do
    sign_in_as @alice

    body = get_list
    assert_equal [], body["docids"]
    assert_equal "", body["text"]
    assert_equal @task.id, body["task_id"]
  end

  test "a task admin can set the list, and gets back what was kept" do
    sign_in_as @alice

    body = post_list("b.json\n\n  a.json  \nb.json\n")

    assert_equal %w[ b.json a.json ], body["docids"],
      "in the order typed, with the blank line, the whitespace and the repeat gone"
    assert_equal "b.json\na.json", body["text"]
    assert_equal %w[ b.json a.json ], @task.reload.docid_list
  end

  test "the list comes back the way it was left" do
    sign_in_as @alice
    post_list("a.json\nb.json")

    assert_equal %w[ a.json b.json ], get_list["docids"]
  end

  test "it says whether this task's workflow reads the list" do
    sign_in_as @alice

    assert_equal "Orderly", get_list["workflow"]
    assert_equal false, get_list["used_by_workflow"], "Orderly ignores it"

    workflow = Workflow.where(name: "SameListForEveryone").first_or_create!(user_states: "needs_kit,has_kit")
    @task.update!(workflow: workflow)
    assert_equal true, get_list["used_by_workflow"]
  end

  test "someone who isn't the task's admin can't read it either" do
    sign_in_as @alice
    post_list("a.json")
    sign_in_as @bob

    assert_match(/must be a task admin/, get_list["error"])
    assert_nil get_list["docids"], "the list isn't handed to someone who can't be shown the tab"
  end

  test "someone who isn't the task's admin can't set it" do
    sign_in_as @bob

    body = post_list("a.json")

    assert_match(/must be a task admin/, body["error"])
    assert_equal [], @task.reload.docid_list
  end
end
