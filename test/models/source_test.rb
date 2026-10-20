require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "Source can be created without a user or task (both optional)" do
    s = Source.new(uid: "src-#{SecureRandom.hex(3)}", filename: "audio.wav")
    assert s.save
    assert_nil s.user
    assert_nil s.task
  end

  test "Source belongs_to user and task when set" do
    s = Source.create!(uid: "src-#{SecureRandom.hex(3)}", user: users(:alice), task: tasks(:alpha_task_one))
    assert_equal users(:alice), s.user
    assert_equal tasks(:alpha_task_one), s.task
  end
end
