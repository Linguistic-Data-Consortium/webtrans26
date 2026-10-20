require "test_helper"

class AccessLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)      # system admin
    @pat = users(:pat)          # portal manager (via the portal_managers group fixture)
    @alice = users(:alice)      # ordinary user
  end

  def mint_for(email, name)
    post access_links_url, params: { email_address: email, name: name }, as: :json
    JSON.parse(@response.body)
  end

  # ── create ───────────────────────────────────────────────────────────────

  test "an admin can create an account and get a one-time link back" do
    sign_in_as @admin
    assert_difference -> { User.count }, 1 do
      @body = mint_for("newbie@example.com", "newbie")
    end
    user = User.find_by(email_address: "newbie@example.com")
    assert_equal "newbie", user.name
    assert_not user.activated, "a new account starts inactive"
    assert user.access_digest.present?, "the link's digest is stored"
    assert_equal @admin.id, user.access_created_by
    assert_match %r{/access/#{user.id}/}, @body["url"]
  end

  test "a portal manager can create a link too" do
    sign_in_as @pat
    assert_difference -> { User.count }, 1 do
      mint_for("pm-invited@example.com", "pminvited")
    end
  end

  test "an ordinary user cannot create a link" do
    sign_in_as @alice
    assert_no_difference -> { User.count } do
      body = mint_for("nope@example.com", "nope")
      assert_equal "Permission denied.", body["error"]
    end
    assert_response :forbidden
  end

  # Recovery path: someone who signed out gets a fresh link on the same
  # address, without a second account being created.
  test "minting for an existing address re-issues a link instead of creating a user" do
    sign_in_as @admin
    mint_for("again@example.com", "again")
    user = User.find_by(email_address: "again@example.com")
    first_digest = user.access_digest

    assert_no_difference -> { User.count } do
      body = mint_for("again@example.com", "ignored-name")
      assert_match %r{/access/#{user.id}/}, body["url"]
    end
    assert_not_equal first_digest, user.reload.access_digest, "a new token replaces the old one"
    assert_equal "again", user.name, "the existing name is kept"
  end

  test "an invalid name comes back as errors, with no account created" do
    sign_in_as @admin
    assert_no_difference -> { User.count } do
      body = mint_for("bad@example.com", "not a valid name")
      assert body["errors"].any? { |e| e.match?(/Name/i) }
    end
  end

  test "a duplicate name comes back as errors" do
    sign_in_as @admin
    assert_no_difference -> { User.count } do
      body = mint_for("other@example.com", @alice.name)
      assert body["errors"].any? { |e| e.match?(/Name/i) }
    end
  end

  # ── show (the link itself) ───────────────────────────────────────────────

  test "opening the link activates the account and signs the user in" do
    sign_in_as @admin
    url = mint_for("clicker@example.com", "clicker")["url"]
    delete session_url # the administrator's own session goes away

    user = User.find_by(email_address: "clicker@example.com")
    assert_difference -> { user.sessions.count }, 1 do
      get url
    end
    assert_redirected_to root_path
    assert user.reload.activated, "the account is activated by the click"
    assert_nil user.access_digest, "the link is spent"
  end

  test "the link works only once" do
    sign_in_as @admin
    url = mint_for("oneshot@example.com", "oneshot")["url"]
    delete session_url

    user = User.find_by(email_address: "oneshot@example.com")
    get url
    assert_redirected_to root_path

    assert_no_difference -> { user.sessions.count } do
      get url
    end
    assert_redirected_to new_session_path
    assert_match(/no longer valid/, flash[:alert])
  end

  test "a wrong token does not sign anyone in" do
    sign_in_as @admin
    mint_for("wrongtoken@example.com", "wrongtoken")
    delete session_url

    user = User.find_by(email_address: "wrongtoken@example.com")
    assert_no_difference -> { user.sessions.count } do
      get access_link_path(user.id, "not-the-real-token")
    end
    assert_redirected_to new_session_path
    assert_not user.reload.activated
  end

  test "an unknown user id does not sign anyone in" do
    get access_link_path(0, "whatever")
    assert_redirected_to new_session_path
  end

  # A user with no outstanding link (digest cleared) can't be signed in by
  # guessing — authenticated? returns false on a nil digest.
  test "a user with no outstanding link cannot be signed in" do
    assert_nil @alice.access_digest
    assert_no_difference -> { @alice.sessions.count } do
      get access_link_path(@alice.id, "anything")
    end
    assert_redirected_to new_session_path
  end

  # ── index ────────────────────────────────────────────────────────────────

  test "index lists the accounts with an outstanding link" do
    sign_in_as @admin
    mint_for("pending@example.com", "pending")
    get access_links_url, as: :json
    rows = JSON.parse(@response.body)["users"]
    row = rows.find { |r| r["email"] == "pending@example.com" }
    assert row, "the pending link is listed"
    assert_equal @admin.name, row["created_by"]
    assert_equal false, row["activated"]
  end

  test "a spent link drops off the index" do
    sign_in_as @admin
    url = mint_for("spent@example.com", "spent")["url"]
    get url # consumes it, and switches the session to the new user
    delete session_url

    sign_in_as @admin
    get access_links_url, as: :json
    emails = JSON.parse(@response.body)["users"].map { |r| r["email"] }
    assert_not_includes emails, "spent@example.com"
  end

  test "an ordinary user cannot list outstanding links" do
    sign_in_as @alice
    get access_links_url, as: :json
    assert_response :forbidden
    assert_equal "Permission denied.", JSON.parse(@response.body)["error"]
  end
end
