require "test_helper"

class ProjectUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)      # owner+admin of alpha
    @bob = users(:bob)          # member of alpha, non-admin
    @charlie = users(:charlie)  # not a member of alpha
    @pat = users(:pat)          # portal manager, not a member of alpha
    @alpha = projects(:alpha)
  end

  # ── create (add user to project) ──────────────────────────────────────────

  test "project admin can add a user to the project" do
    sign_in_as @alice
    assert_difference -> { @alpha.users.count }, 1 do
      post project_users_url, params: { project_id: @alpha.id, user_id: @charlie.id }, as: :json
    end
    body = JSON.parse(@response.body)
    assert_match(/#{@charlie.name} has been added/, body["ok"])
  end

  test "non-admin member cannot add a user" do
    sign_in_as @bob
    assert_no_difference -> { @alpha.users.count } do
      post project_users_url, params: { project_id: @alpha.id, user_id: @charlie.id }, as: :json
    end
    body = JSON.parse(@response.body)
    assert_equal "permission denied", body["error"]
  end

  test "non-member cannot add a user" do
    sign_in_as @charlie
    assert_no_difference -> { @alpha.users.count } do
      post project_users_url, params: { project_id: @alpha.id, user_id: @bob.id }, as: :json
    end
    body = JSON.parse(@response.body)
    assert_equal "permission denied", body["error"]
  end

  # Regression: a Portal Manager who is NOT a project member and NOT a
  # system admin must still be allowed to add users to any project
  # (SessionsHelper#project_owner? cascades through portal_manager?).
  test "portal manager can add a user to a project they don't belong to" do
    sign_in_as @pat
    assert_difference -> { @alpha.users.count }, 1 do
      post project_users_url, params: { project_id: @alpha.id, user_id: @charlie.id }, as: :json
    end
    body = JSON.parse(@response.body)
    assert_match(/#{@charlie.name} has been added/, body["ok"])
  end

  # Regression: a request with no user_id (a client bug) used to raise
  # RecordNotFound and return a 404 the dashboard couldn't report.
  test "a missing user_id is a JSON error, not a 404" do
    sign_in_as @alice
    assert_no_difference -> { @alpha.users.count } do
      post project_users_url, params: { project_id: @alpha.id }, as: :json
    end
    assert_response :success
    assert_equal "no such user", JSON.parse(@response.body)["error"]
  end

  test "adding a user who is already a member is a JSON error, not a duplicate row" do
    sign_in_as @alice
    assert_no_difference -> { @alpha.users.count } do
      post project_users_url, params: { project_id: @alpha.id, user_id: @bob.id }, as: :json
    end
    assert_response :success
    assert_match(/#{@bob.name} is already a member/, JSON.parse(@response.body)["error"])
  end

  # ── destroy (remove user from project) ────────────────────────────────────

  test "project admin can remove a user from the project" do
    sign_in_as @alice
    pu = project_users(:bob_on_alpha)
    assert_difference -> { @alpha.users.count }, -1 do
      delete project_user_url(pu), as: :json
    end
    body = JSON.parse(@response.body)
    assert_match(/#{@bob.name} has been removed/, body["ok"])
  end

  test "non-admin cannot remove a user" do
    sign_in_as @bob
    pu = project_users(:alice_owns_alpha)
    assert_no_difference -> { @alpha.users.count } do
      delete project_user_url(pu), as: :json
    end
    body = JSON.parse(@response.body)
    assert_equal "permission denied", body["error"]
  end

  # ── update (toggle owner/admin flags) ─────────────────────────────────────

  test "project owner can promote a member to admin" do
    sign_in_as @alice
    pu = project_users(:bob_on_alpha)
    assert_not pu.admin?
    patch project_user_url(pu), params: { admin: true }, as: :json
    assert_response :success
    assert pu.reload.admin?
  end

  test "project owner can demote an admin" do
    sign_in_as @alice
    pu = project_users(:bob_on_alpha)
    pu.update!(admin: true)
    patch project_user_url(pu), params: { admin: false }, as: :json
    assert_not pu.reload.admin?
  end

  test "project owner can transfer ownership by flipping owner flag" do
    sign_in_as @alice
    pu = project_users(:bob_on_alpha)
    patch project_user_url(pu), params: { owner: true }, as: :json
    assert_response :success
    assert pu.reload.owner?
  end

  test "non-owner (plain admin) cannot change owner/admin flags" do
    sign_in_as @alice
    bob_pu = project_users(:bob_on_alpha)
    bob_pu.update!(admin: true, owner: false)

    # Sign in as bob (now a non-owner admin) and try to promote himself
    delete session_url
    sign_in_as @bob
    patch project_user_url(bob_pu), params: { owner: true }, as: :json
    body = JSON.parse(@response.body)
    assert_equal "permission denied", body["error"]
    assert_not bob_pu.reload.owner?
  end
end
