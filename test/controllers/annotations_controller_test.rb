require "test_helper"

# Posts message batches the way the waveform does (modification2.js submit_form)
# and checks the responses it sends back. The annotation *writer* also has to
# describe the nodes it just made — that response used to be read out of the
# nodes table, which nothing maintains any more.
class AnnotationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Annotation.where(id: 0).first_or_create # the placeholder valueless children point at
    @user = users(:alice)
    @task = tasks(:alpha_task_one)
    @task_user = task_users(:alice_admin_alpha_task_one)
    @task_user.update!(state: "has_kit")
    @class_def = ClassDef.create!(name: "AnnCtl-#{SecureRandom.hex(3)}")
    @tree = Tree.create!(uid: "ann-ctl-#{SecureRandom.hex(3)}", class_def: @class_def, version: 2)
    @kit = Kit.create!(
      task_id: @task.id, kit_type_id: @task.kit_type_id, tree_id: @tree.id,
      user_id: @user.id, state: "assigned", uid: "ann-ctl-kit-#{SecureRandom.hex(3)}"
    )
    @task_user.update!(kit_oid: @kit.uid)
    @user.update!(current_task_user_id: @task_user.id)
    # Every real tree opens with a 'new' annotation; annotatex chains each
    # message onto the previous annotation, so there has to be one to chain to.
    Annotation.create!(
      tree_id: @tree.id, task_id: @task.id, user_id: @user.id, kit_id: @kit.id,
      message: "new", last_iid: 0
    )
    sign_in_as @user
  end

  def submit(messages)
    post annotations_url, params: {
      task_user_id: @task_user.id,
      json: { kit_uid: @kit.uid, client_time: 1, messages: messages }.to_json
    }, as: :json
    JSON.parse(@response.body)
  end

  # Each response answers one message and is built from that message's own
  # annotation — not from a replay of the tree, which is the state *after* the
  # whole batch. Before that change both of these reported "second", so the
  # first message was told its own change hadn't taken.
  test "two changes to one node in one request each get their own value back" do
    submit([ { node: 0, message: "add",
               value: { value: "1:SegmentListItem,2:Arc,3:Text,4:Speaker" } } ])

    r = submit([
      { node: 3, message: "change", value: { value: "first" } },
      { node: 3, message: "change", value: { value: "second" } }
    ])

    assert_equal 2, r.size
    assert_equal({ "value" => "first" },  r[0]["node"]["value"])
    assert_equal({ "value" => "second" }, r[1]["node"]["value"])
    # Distinct rows, in order.
    assert_operator r[1]["annotation_id"], :>, r[0]["annotation_id"]
  end

  # What confirm_message (modification2.js) compares, and nothing more. The
  # structural fields the replay used to supply — parent_id, and the node's name
  # on a change — are read nowhere in app/javascript and are gone with it.
  test "a change response carries the iid and the value it stored" do
    submit([ { node: 0, message: "add",
               value: { value: "1:SegmentListItem,2:Arc,3:Text,4:Speaker" } } ])

    r = submit([ { node: 3, message: "change", value: { value: "hello" } } ]).first

    assert_equal 3, r["old_id"]
    assert_equal "change", r["message"]
    assert_equal({ "value" => "hello" }, r["node"]["value"])
    assert_equal 3, r["node"]["meta"]["id"]
    assert_nil r["parent_id"]
  end

  # Times arrive as a real span, and the client's comparison keys off type.
  test "a real-valued change keeps its type" do
    submit([ { node: 0, message: "add",
               value: { value: "1:SegmentListItem,2:Arc,3:Text,4:Speaker" } } ])

    r = submit([ { node: 2, message: "change",
                   value: { docid: "a.wav", beg: 1.5, end: 3.0, type: "real" } } ]).first

    assert_equal "real", r["node"]["value"]["type"]
    assert_equal 1.5, r["node"]["value"]["beg"]
    assert_equal "a.wav", r["node"]["value"]["docid"]
  end

  # An add answers with the list item it created, read out of the group string
  # rather than looked up: iid, name, and the string itself as the value.
  test "an add response describes the list item from its group string" do
    r = submit([ { node: 0, message: "add",
                   value: { value: "5:SegmentListItem,6:Arc,7:Text,8:Speaker" } } ]).first

    assert_equal 1, r["nodes"].size
    node = r["nodes"].first
    assert_equal 5, node["meta"]["id"]
    assert_equal "SegmentListItem", node["meta"]["name"]
    assert_equal "5:SegmentListItem,6:Arc,7:Text,8:Speaker", node["value"]["value"]
  end

  # The editor's opening move for a new segment: add the list item plus its
  # children, then set each child's value.
  def add_segment_messages(base)
    [
      { node: 0, message: "add",
        value: { value: "#{base}:SegmentListItem,#{base + 1}:Arc,#{base + 2}:Text,#{base + 3}:Speaker" } },
      { node: base + 1, message: "change", value: { docid: "a.wav", beg: 1.5, end: 3.0, type: "real" } },
      { node: base + 2, message: "change", value: { value: "some words" } },
      { node: base + 3, message: "change", value: { value: "alice" } }
    ]
  end

  test "a segment batch succeeds and describes what it created" do
    body = submit(add_segment_messages(10))
    assert_response :success

    add = body[0]
    assert_equal "add", add["message"]
    assert_equal 1, add["nodes"].length, "the list item carries the add; its children start valueless"
    assert_equal "SegmentListItem", add["nodes"][0].dig("meta", "name")
    assert_equal 10, add["nodes"][0].dig("meta", "id")

    # Regression: these were read out of the nodes table, so once that stopped
    # being written the change branch raised NoMethodError on nil and the
    # editor hung waiting for a response that never came. It can't raise now —
    # the answer is read off the annotation the loop was handed.
    arc = body[1]
    assert_equal "change", arc["message"]
    assert_equal 11, arc["old_id"]
    assert_equal 1.5, arc.dig("node", "value", "beg")
    assert_equal 3.0, arc.dig("node", "value", "end")
    assert_equal "real", arc.dig("node", "value", "type")

    text = body[2]
    assert_equal "some words", text.dig("node", "value", "value")

    # `parent_id` and the node's `name` used to ride along on a change, out of
    # the tree replay. Both need structure an annotation doesn't carry, neither
    # is read anywhere in app/javascript, and the replay they came from was the
    # whole cost — so they went with it.
    assert_nil arc["parent_id"]
    assert_nil text.dig("node", "meta", "name")
  end

  test "the batch is recorded as annotations" do
    assert_difference -> { Annotation.where(tree_id: @tree.id).count }, 4 do
      submit(add_segment_messages(10))
    end
  end

  test "a second segment in a later request also succeeds" do
    submit(add_segment_messages(10))
    body = submit(add_segment_messages(20))
    assert_response :success
    assert_equal 20, body[0]["nodes"][0].dig("meta", "id")
    assert_equal 21, body[1]["old_id"]
    assert_equal({ "docid" => "a.wav", "beg" => 1.5, "end" => 3.0, "type" => "real" },
                 body[1]["node"]["value"])
  end

  test "editing a segment's text returns the new value" do
    submit(add_segment_messages(10))
    body = submit([ { node: 12, message: "change", value: { value: "corrected" } } ])
    assert_response :success
    assert_equal "corrected", body[0].dig("node", "value", "value")
  end

  test "deleting a segment succeeds" do
    submit(add_segment_messages(10))
    body = submit([ { node: 10, message: "delete", value: nil } ])
    assert_response :success
    assert_equal "delete", body[0]["message"]
    assert_not NodeDerivation.for_tree(@tree.id).nodes.key?(10)
  end

  test "the derived tree reflects the whole session" do
    submit(add_segment_messages(10))
    submit(add_segment_messages(20))
    submit([ { node: 20, message: "delete", value: nil } ])

    nodes = NodeDerivation.for_tree(@tree.id).nodes
    assert_equal [ 10, 11, 12, 13 ], nodes.keys.sort
    assert_equal "some words", NodeDerivation.for_tree(@tree.id).value_for(nodes[12])[:value]
  end
end
