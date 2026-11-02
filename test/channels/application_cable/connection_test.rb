require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with a live session" do
    session = users(:alice).sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    cookies.signed[:session_id] = session.id
    connect
    assert_equal users(:alice), connection.current_user
  end

  test "refuses a session past the idle limit" do
    session = users(:alice).sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    session.update_columns(updated_at: 15.days.ago)
    cookies.signed[:session_id] = session.id
    assert_reject_connection { connect }
  end
end
