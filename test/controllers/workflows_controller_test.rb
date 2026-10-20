require "test_helper"

class WorkflowsControllerTest < ActionDispatch::IntegrationTest
  test "GET /workflows lists workflows for a project_manager" do
    sign_in_as users(:admin)
    get workflows_url, as: :json
    assert_response :success
    body = JSON.parse(@response.body)
    names = body.map { |w| w["name"] }
    assert_includes names, workflows(:orderly).name
    assert_includes names, workflows(:on_the_fly).name
  end

  test "GET /workflows is permission-gated for non-managers" do
    sign_in_as users(:alice)
    get workflows_url, as: :json
    assert_response :forbidden
    body = JSON.parse(@response.body)
    assert_equal "Permission denied.", body["error"]
  end

  test "GET /workflows/:id returns the workflow with the type-options menu" do
    sign_in_as users(:admin)
    get workflow_url(workflows(:orderly)), as: :json
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal workflows(:orderly).id, body["id"]
    assert_equal workflows(:orderly).name, body["name"]
    assert_equal %w[Orderly OnTheFly], body["types"]
  end

  test "POST /workflows creates a new workflow for admins" do
    sign_in_as users(:admin)
    assert_difference -> { Workflow.count }, 1 do
      post workflows_url, params: { workflow: { name: "BrandNewFlow" } }, as: :json
    end
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "BrandNewFlow", body["name"]
  end

  test "POST /workflows is admin-only" do
    sign_in_as users(:alice)
    assert_no_difference -> { Workflow.count } do
      post workflows_url, params: { workflow: { name: "Sneaky" } }, as: :json
    end
    body = JSON.parse(@response.body)
    assert_equal "Permission denied.", body["error"]
  end

  test "PATCH /workflows/:id updates description for admin" do
    sign_in_as users(:admin)
    patch workflow_url(workflows(:orderly)), params: { workflow: { description: "Renamed desc" } }, as: :json
    assert_response :success
    assert_equal "Renamed desc", workflows(:orderly).reload.description
  end

  test "DELETE /workflows/:id removes the workflow for admin" do
    target = Workflow.create!(name: "Doomed-#{SecureRandom.hex(2)}")
    sign_in_as users(:admin)
    assert_difference -> { Workflow.count }, -1 do
      delete workflow_url(target), as: :json
    end
    assert_response :success
  end

  test "DELETE /workflows/:id is admin-only" do
    sign_in_as users(:alice)
    assert_no_difference -> { Workflow.count } do
      delete workflow_url(workflows(:orderly)), as: :json
    end
    body = JSON.parse(@response.body)
    assert_equal "Permission denied.", body["error"]
  end
end
