require "test_helper"

# The Kits tab's text dialog. Each entry is a docid, optionally with a user_id
# — "foo.wav user_id=alice" — and the kit is made for that person.
#
# user_id is whatever was typed, so it's resolved here. An entry naming a user
# who doesn't exist makes no kit at all: a kit owned by nobody looks like an
# ordinary unassigned one and would go to whoever asked for work next.
class CreateKitsFromKitsTabTest < ActionDispatch::IntegrationTest
  setup do
    @task = tasks(:alpha_task_one)
    @alice = users(:alice)
    sign_in_as @alice
  end

  def create(kits)
    post "/create_kits_from_kits_tab", params: { task_id: @task.id, kits: kits }, as: :json
    JSON.parse(@response.body)
  end

  def kits = Kit.where(task_id: @task.id).order(:id)

  test "a docid on its own makes a kit belonging to nobody in particular" do
    body = create([ { docid: "foo.wav" } ])

    assert_equal 1, body["created"]
    assert_equal [], body["errors"]
    assert_equal "foo.wav", kits.sole.source_uid
    assert_nil kits.sole.user_id
    assert_equal "unassigned", kits.sole.state
  end

  test "a user's id gives them the kit" do
    create([ { docid: "foo.wav", user_id: @alice.id.to_s } ])

    assert_equal @alice.id, kits.sole.user_id
  end

  test "a user's name gives them the kit" do
    create([ { docid: "foo.wav", user_id: @alice.name } ])

    assert_equal @alice.id, kits.sole.user_id
  end

  test "a user's email address gives them the kit" do
    create([ { docid: "foo.wav", user_id: @alice.email_address.upcase } ])

    assert_equal @alice.id, kits.sole.user_id, "matched however it was capitalised"
  end

  test "an entry naming nobody makes no kit, and says which" do
    body = create([ { docid: "foo.wav", user_id: "nobody" } ])

    assert_equal 0, body["created"]
    assert_equal [ "foo.wav: no user 'nobody'" ], body["errors"]
    assert_equal 0, kits.count, "better no kit than one owned by nobody"
  end

  test "the entries that can be made are made" do
    body = create([
      { docid: "a.wav" },
      { docid: "b.wav", user_id: @alice.name },
      { docid: "c.wav", user_id: "nobody" },
      { docid: "d.wav", user_id: users(:bob).name }
    ])

    assert_equal 3, body["created"]
    assert_equal [ "c.wav: no user 'nobody'" ], body["errors"]
    assert_equal %w[ a.wav b.wav d.wav ], kits.pluck(:source_uid)
    assert_equal [ nil, @alice.id, users(:bob).id ], kits.pluck(:user_id)
  end

  test "an s3 url is a docid like any other" do
    uid = "s3://my-bucket/recordings/REC_passage_reading.wav"
    create([ { docid: uid, user_id: @alice.name } ])

    assert_equal uid, kits.sole.source_uid
    assert_equal uid, kits.sole.source[:uid], "the source hash carries it too"
  end

  test "someone who doesn't administer the task can't make kits on it" do
    sign_in_as users(:bob)   # a member of the task, not an admin

    body = create([ { docid: "foo.wav", user_id: @alice.name } ])

    assert_match(/must be a task admin/, body["errors"].first)
    assert_equal 0, body["created"]
    assert_equal 0, kits.count
  end

  test "the ids of what was made come back" do
    body = create([ { docid: "a.wav" }, { docid: "b.wav" } ])

    assert_equal kits.pluck(:id), body["kit_ids"]
  end
end
