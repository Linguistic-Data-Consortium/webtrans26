require "test_helper"

class InvitesControllerTest < ActionDispatch::IntegrationTest
  def create_pending_invite(sender:)
    user = User.new(email_address: "invitee_#{SecureRandom.hex(3)}@example.com", password: User.new_token)
    user.save(validate: false) # skip the name/password length validations — the invite flow fills these in later
    user.create_invite_digest(sender.id)
    user
  end

  # ── index ────────────────────────────────────────────────────────────────

  test "index returns the invites sent by the current user (project_manager gated)" do
    sign_in_as users(:admin)
    # admin is project_manager via portal_manager via admin? — the endpoint is gated on :project_manager
    get invites_url, as: :json
    assert_response :success
    body = JSON.parse(@response.body)
    assert body.key?("users")
    assert body.key?("projects")
    assert body.key?("tasks_index")
  end

  test "index returns permission-denied for a regular user" do
    sign_in_as users(:alice)
    get invites_url, as: :json
    assert_response :forbidden
    body = JSON.parse(@response.body)
    assert_equal "Permission denied.", body["error"]
  end

  # ── edit (recipient clicks the invite link) ─────────────────────────────

  test "edit with a valid invite token activates the pending user and redirects to the password setup page" do
    pending = create_pending_invite(sender: users(:admin))
    assert_not pending.activated?

    get edit_invite_path(pending.invite_token, email: pending.email_address)
    pending.reload
    assert pending.activated?, "invite click should activate the user"
    follow_redirect!
    # The redirect target includes the password_reset_token, which is the user's regular reset flow.
    assert_match %r{/passwords/[^/]+/edit}, request.fullpath
    assert_match(/activated/i, flash[:success])
  end

  test "edit with an invalid token does not activate and redirects to root" do
    pending = create_pending_invite(sender: users(:admin))

    get edit_invite_path("not-a-real-token", email: pending.email_address)
    pending.reload
    assert_not pending.activated?
    # `valid_user` before_action redirects to root silently before reaching the flash-setting branch.
    assert_redirected_to root_url
  end

  test "edit for an already-activated user short-circuits with a friendly message" do
    pending = create_pending_invite(sender: users(:admin))
    pending.activate
    original_activated_at = pending.activated_at

    get edit_invite_path(pending.invite_token, email: pending.email_address)
    assert_redirected_to root_url
    assert_match(/already activated/i, flash[:success])
    # The activation timestamp should not be touched a second time.
    assert_equal original_activated_at.to_i, pending.reload.activated_at.to_i
  end

  test "edit with a wrong email param fails even with a correct-looking token" do
    pending = create_pending_invite(sender: users(:admin))

    get edit_invite_path(pending.invite_token, email: "stranger@example.com")
    assert_not pending.reload.activated?
    # Same `valid_user` redirect with no flash set.
    assert_redirected_to root_url
  end
end
