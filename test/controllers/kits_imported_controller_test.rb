require "test_helper"

# POST /kits/imported is what a transcribe_text_only kit asks for when it
# opens: the imported graph covering its audio, matched by stem, in the tier
# its kit type names. The spans come back flattened, since that's what the tool
# needs — a caption over each segment, and the times to create segments at.
class KitsImportedControllerTest < ActionDispatch::IntegrationTest
  setup do
    Annotation.where(id: 0).first_or_create
    @alice = users(:alice)
    @task = tasks(:alpha_task_one)
    @class_def = ClassDef.where(name: "ArcTranscription").first_or_create!
    root = NodeClass.where(name: "ArcTranscription:Root").first_or_create!(class_def: @class_def)
    @kit_type = KitType.create!(name: "imported-ctl-#{SecureRandom.hex(3)}", node_class: root)
    @kit_type.constraints = { "transcribe_text_only" => "transcribe_text_only" }
    @kit_type.save!
    @tree = Tree.create!(uid: "imported-ctl-#{SecureRandom.hex(3)}", class_def: @class_def, version: 2)
    @kit = Kit.create!(
      task_id: @task.id, kit_type_id: @kit_type.id, tree_id: @tree.id,
      user_id: @alice.id, state: "assigned",
      uid: "imported-ctl-kit-#{SecureRandom.hex(3)}",
      source_uid: "/audio/AAA_passage.wav"
    )
  end

  # Deliberately spelled differently from the kit's source: a bare id, no
  # directory and no extension, which is how a transcript names its documents.
  def import(name: "reference", rows: nil, docid: "AAA_passage")
    rows ||= [
      { beg: 0.5, end: 3.0, labels: { "Text" => "first line" } },
      { beg: 3.0, end: 7.0, labels: { "Text" => "second line" } }
    ]
    ImportedGraph.build(docid: docid, name: name, rows: rows, source: "sample.tsv", format: "tsv")
  end

  def fetch(uid: @kit.uid)
    post "/kits/imported", params: { uid: uid }, as: :json
    JSON.parse(@response.body)
  end

  test "it returns the spans covering the kit's audio, matched by stem" do
    import
    sign_in_as @alice

    body = fetch

    assert_nil body["error"]
    assert_equal "AAA_passage", body["docid"]
    assert_equal "reference", body["tier"]
    assert_equal "sample.tsv", body["source"]
    assert_equal [ "first line", "second line" ], body["rows"].map { |r| r["text"] }
    assert_equal [ [ 0.5, 3.0 ], [ 3.0, 7.0 ] ], body["rows"].map { |r| [ r["beg"], r["end"] ] }
    assert_equal %w[ beg end text ], body["rows"].first.keys.sort - [],
      "only what the tool needs: times and text"
  end

  test "the constraint's value names the tier" do
    import(name: "reference")
    import(name: "asr", rows: [ { beg: 0.4, end: 3.1, labels: { "Text" => "asr guess" } } ])
    @kit_type.update!(constraints: { "transcribe_text_only" => "asr" })
    sign_in_as @alice

    assert_equal [ "asr guess" ], fetch["rows"].map { |r| r["text"] }
  end

  test "set as a plain flag it reads the reference tier" do
    import(name: "reference")
    import(name: "asr", rows: [ { beg: 0.4, end: 3.1, labels: { "Text" => "asr guess" } } ])
    sign_in_as @alice

    assert_equal [ "first line", "second line" ], fetch["rows"].map { |r| r["text"] }
  end

  test "a kit whose audio has nothing imported is told so, by tier" do
    import(name: "reference", docid: "SOMETHING_ELSE")
    sign_in_as @alice

    body = fetch
    assert_match(/no 'reference' graph imported for \/audio\/AAA_passage.wav/, body["error"])
    assert_match(/nothing imported for that audio/, body["error"])
    assert_equal "reference", body["tier"]
    assert_equal [], body["available"]
    assert_nil body["rows"]
  end

  # The way this goes wrong in practice: the import named the tier something
  # else, and a kit type set as a plain flag asks for 'reference'. The message
  # has to name what's actually there or the mismatch isn't visible.
  test "audio with tiers under other names says which ones it has" do
    import(name: "ref")
    import(name: "asr", rows: [ { beg: 0.4, end: 3.1, labels: { "Text" => "asr guess" } } ])
    sign_in_as @alice

    body = fetch
    assert_match(/no 'reference' graph imported/, body["error"])
    assert_match(/that audio has: asr, ref/, body["error"])
    assert_equal %w[ asr ref ], body["available"]
  end

  test "an unknown kit is an error, not an exception" do
    sign_in_as @alice

    assert_equal "no such kit", fetch(uid: "nope")["error"]
  end
end
