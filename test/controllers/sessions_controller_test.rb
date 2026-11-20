require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "GET /session/new renders the sign-in form" do
    get new_session_path
    assert_response :success
    assert_select "form[action=?]", session_path
    assert_select "input[name='email_address']"
    assert_select "input[name='password']"
  end

  test "POST /session signs in an activated user and sets the session cookie" do
    assert_difference -> { users(:alice).sessions.count }, 1 do
      sign_in_as users(:alice)
    end
    assert_redirected_to root_url
    assert cookies[:session_id].present?
  end

  test "POST /session rejects wrong password" do
    post session_url, params: { email_address: users(:alice).email_address, password: "wrong-password" }
    assert_redirected_to new_session_path
    assert_match(/Try another email address or password/i, flash[:alert])
    assert cookies[:session_id].blank?
  end

  test "POST /session blocks unactivated users" do
    post session_url, params: { email_address: users(:unactivated).email_address, password: "password123" }
    assert_redirected_to new_session_path
    assert_match(/hasn.?t been activated/i, flash[:alert])
  end

  test "DELETE /session terminates the session" do
    sign_in_as users(:alice)
    assert cookies[:session_id].present?

    assert_difference -> { Session.count }, -1 do
      delete session_url
    end
    assert_redirected_to new_session_path
    assert cookies[:session_id].blank?
  end


  # ── idle timeout ─────────────────────────────────────────────────────────

  test "a session unused for over two hours is refused and deleted" do
    alice = users(:alice)
    sign_in_as alice
    session = alice.sessions.order(:id).last
    session.update_columns(updated_at: (2.hours + 1.minute).ago)
    get user_path(alice)
    assert_redirected_to new_session_path
    assert_not Session.exists?(session.id)
  end

  test "a session used within two hours carries on" do
    alice = users(:alice)
    sign_in_as alice
    alice.sessions.order(:id).last.update_columns(updated_at: (2.hours - 1.minute).ago)
    get user_path(alice)
    assert_response :success
  end

  test "someone who keeps working is never signed out" do
    alice = users(:alice)
    sign_in_as alice
    # Six hours of a request every 20 minutes: never two hours idle.
    18.times do
      travel 20.minutes
      get user_path(alice)
      assert_response :success
    end
  ensure
    travel_back
  end

  test "using a session pushes its expiry back, at most every five minutes" do
    alice = users(:alice)
    sign_in_as alice
    session = alice.sessions.order(:id).last
    session.update_columns(updated_at: 6.minutes.ago)
    get user_path(alice)
    assert_operator session.reload.updated_at, :>, 1.minute.ago

    session.update_columns(updated_at: 2.minutes.ago)
    stamp = session.reload.updated_at
    get user_path(alice)
    assert_equal stamp, session.reload.updated_at
  end

  # ── what a signed-out request gets ─────────────────────────────────────

  test "a signed-out JSON request gets a 401 that says the session ended" do
    post annotations_url, params: { task_user_id: 1, json: "{}" }, as: :json
    assert_response :unauthorized
    assert JSON.parse(@response.body)["session_expired"]
  end

  test "a signed-out page load comes back to that page after signing in" do
    get user_path(users(:alice))
    assert_redirected_to new_session_path
    sign_in_as users(:alice)
    assert_redirected_to user_url(users(:alice))
  end

  # Coming back to /annotations, which has no page, was an error after signing in.
  test "a signed-out save isn't remembered as somewhere to come back to" do
    post annotations_url, params: { task_user_id: 1, json: "{}" }, as: :json
    sign_in_as users(:alice)
    assert_redirected_to root_url
  end

  # ── inactivity ───────────────────────────────────────────────────────────

  test "signing in to an account unused past the limit disables it and says why" do
    alice = users(:alice)
    alice.update_columns(last_active_at: 181.days.ago)
    assert_no_difference -> { alice.sessions.count } do
      sign_in_as alice
    end
    assert_redirected_to new_session_path
    assert_equal SessionsController::DISABLED, flash[:alert]
    assert alice.reload.disabled_for_inactivity?
  end

  test "a wrong password on a disabled account says nothing about it" do
    alice = users(:alice)
    alice.update_columns(last_active_at: 181.days.ago)
    post session_url, params: { email_address: alice.email_address, password: "wrong" }
    assert_equal SessionsController::FAILED, flash[:alert]
  end

  test "signing in and using the app records activity" do
    alice = users(:alice)
    alice.update_columns(last_active_at: 100.days.ago)
    sign_in_as alice
    assert_in_delta Time.current, alice.reload.last_active_at, 5
  end

  test "an administrator re-enabling the account lets it sign in again" do
    alice = users(:alice)
    alice.update_columns(last_active_at: 181.days.ago)
    alice.disable_for_inactivity!
    sign_in_as users(:pat) # portal manager
    get unactivated_users_url, as: :json
    assert JSON.parse(@response.body)["users"].find { |u| u["id"] == alice.id }["disabled_at"]
    patch activate_user_url(alice), as: :json
    delete session_url

    sign_in_as alice
    assert_redirected_to root_url
  end

  # ── lockout ──────────────────────────────────────────────────────────────

  def fail_sign_in(user, times)
    times.times { post session_url, params: { email_address: user.email_address, password: "wrong-#{SecureRandom.hex(2)}" } }
  end

  test "three wrong passwords lock the account, and then the right one is refused too" do
    alice = users(:alice)
    fail_sign_in(alice, 2)
    assert_not alice.reload.locked?, "two failures aren't enough"
    fail_sign_in(alice, 1)
    assert alice.reload.locked?

    assert_no_difference -> { alice.sessions.count } do
      sign_in_as alice
    end
    assert_redirected_to new_session_path
    assert_equal SessionsController::FAILED, flash[:alert]
  end

  test "the lock lasts 30 minutes, then the account signs in again" do
    alice = users(:alice)
    fail_sign_in(alice, 3)
    travel 29.minutes do
      sign_in_as alice
      assert_redirected_to new_session_path
    end
    travel 31.minutes do
      sign_in_as alice
      assert_redirected_to root_url
      assert_not alice.reload.locked?
    end
  end

  test "a successful sign-in starts the count again" do
    alice = users(:alice)
    fail_sign_in(alice, 2)
    sign_in_as alice
    assert_equal 0, alice.reload.failed_sign_in_count
    fail_sign_in(alice, 2)
    assert_not alice.reload.locked?
  end

  test "a locked account gets the same answer as a wrong password or an unknown address" do
    fail_sign_in(users(:alice), 3)
    sign_in_as users(:alice)
    assert_redirected_to new_session_path, "the right password is refused while locked"
    locked = flash[:alert]
    post session_url, params: { email_address: "nobody@example.com", password: "whatever" }
    unknown = flash[:alert]
    post session_url, params: { email_address: users(:bob).email_address, password: "wrong" }
    wrong = flash[:alert]
    assert_equal [ locked ], [ unknown, wrong ].uniq
  end

  test "failures on one account don't lock another" do
    fail_sign_in(users(:alice), 3)
    sign_in_as users(:bob)
    assert_redirected_to root_url
  end

  test "a completed password reset unlocks the account" do
    alice = users(:alice)
    fail_sign_in(alice, 3)
    assert alice.reload.locked?
    get edit_password_path(alice.password_reset_token)
    follow_redirect!
    patch reset_password_path, params: { password: GOOD_PASSWORD, password_confirmation: GOOD_PASSWORD }
    assert_not alice.reload.locked?
    sign_in_as alice, password: GOOD_PASSWORD
    assert_redirected_to root_url
  end

  test "an access link unlocks the account" do
    alice = users(:alice)
    fail_sign_in(alice, 3)
    assert alice.reload.locked?
    get access_link_path(alice.id, alice.create_access_digest(users(:admin).id))
    assert_not alice.reload.locked?
  end
end

