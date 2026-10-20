require "test_helper"

# The list itself: one row per document, replaced wholesale from a textarea.
class TaskDocidTest < ActiveSupport::TestCase
  setup do
    @task = tasks(:alpha_task_one)
  end

  test "the list keeps the order it was entered in" do
    TaskDocid.replace_for(@task.id, [ "c.json", "a.json", "b.json" ])

    assert_equal %w[ c.json a.json b.json ], @task.reload.docid_list
    assert_equal [ 0, 1, 2 ], TaskDocid.for_task(@task.id).in_order.pluck(:position)
  end

  test "replacing means replacing, not adding to" do
    TaskDocid.replace_for(@task.id, %w[ a.json b.json ])
    TaskDocid.replace_for(@task.id, %w[ b.json c.json ])

    assert_equal %w[ b.json c.json ], @task.reload.docid_list
  end

  test "blank lines, stray whitespace and repeats don't become documents" do
    TaskDocid.replace_for(@task.id, [ "a.json", "", "  b.json  ", "a.json", "   ", "c.json" ])

    assert_equal %w[ a.json b.json c.json ], @task.reload.docid_list
  end

  test "a task's list is its own" do
    other = tasks(:alpha_task_two)
    TaskDocid.replace_for(@task.id, %w[ mine.json ])
    TaskDocid.replace_for(other.id, %w[ theirs.json ])

    assert_equal %w[ mine.json ], @task.reload.docid_list
    assert_equal %w[ theirs.json ], other.reload.docid_list
  end

  test "text_for round-trips a textarea" do
    text = "a.json\nb.json\nc.json"
    TaskDocid.replace_for(@task.id, text.split("\n"))

    assert_equal text, TaskDocid.text_for(@task.id)
  end

  test "an empty list is a list with nothing on it" do
    TaskDocid.replace_for(@task.id, %w[ a.json ])
    TaskDocid.replace_for(@task.id, [])

    assert_equal [], @task.reload.docid_list
    assert_equal "", TaskDocid.text_for(@task.id)
  end

  test "the same document can't be on one list twice" do
    TaskDocid.replace_for(@task.id, %w[ a.json ])

    assert_raises(ActiveRecord::RecordNotUnique) do
      TaskDocid.create!(task_id: @task.id, docid: "a.json")
    end
  end

  test "deleting a task takes its list" do
    task = Task.create!(
      name: "docid-list-#{SecureRandom.hex(3)}", project: projects(:alpha),
      workflow: workflows(:orderly), kit_type: kit_types(:basic)
    )
    TaskDocid.replace_for(task.id, %w[ a.json b.json ])

    task.destroy!

    assert_equal 0, TaskDocid.for_task(task.id).count
  end
end
