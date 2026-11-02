require "test_helper"

class GuideChannelTest < ActionCable::Channel::TestCase
  test "update saves the guide's own fields" do
    stub_connection current_user: users(:alice)
    subscribe gname: "tour"
    perform :update, "currentstep" => 3, "complete" => true
    guide = Guide.find_by(user_id: users(:alice).id, name: "tour")
    assert_equal 3, guide.currentstep
    assert guide.complete
  end

  test "update can't move the row onto another user's guide" do
    stub_connection current_user: users(:alice)
    subscribe gname: "tour"
    perform :update, "user_id" => users(:bob).id, "name" => "other", "currentstep" => 2
    guide = Guide.find_by(name: "tour")
    assert_equal users(:alice).id, guide.user_id
    assert_equal 2, guide.currentstep
  end
end
