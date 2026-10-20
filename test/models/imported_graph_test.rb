require "test_helper"

# An imported graph is the same formalism as the annotator side — anchors,
# spans between them, labels on the spans — without the expansion that records
# who did what. These check the parts that make it worth storing separately:
# anchors shared rather than duplicated, whole-graph replacement, and the range
# query the denormalized times exist for.
class ImportedGraphTest < ActiveSupport::TestCase
  DOCID = "/test_tone_10s.wav".freeze

  # Two contiguous segments: the first ends exactly where the second begins.
  def contiguous
    [
      { beg: 0.5, end: 3.0, labels: { "Text" => "first", "Speaker" => "Alice" } },
      { beg: 3.0, end: 7.0, labels: { "Text" => "second", "Speaker" => "Bob" } }
    ]
  end

  def build(rows, name: "reference", docid: DOCID)
    ImportedGraph.build(docid: docid, name: name, rows: rows)
  end

  test "a span becomes an arc between two anchors, with its fields as labels" do
    graph = build(contiguous)

    arc = ImportedArc.by_graph(graph.id).in_time_order.first
    assert_equal "Segment", arc.name
    assert_equal 0.5, arc.beg.to_f
    assert_equal 3.0, arc[:end].to_f
    assert_equal({ "Text" => "first", "Speaker" => "Alice" }, arc.label_values)
    assert_equal [ 0.5, 3.0 ], [ arc.beg_node.time.to_f, arc.end_node.time.to_f ],
      "the arc's anchors carry the same times its columns copy"
  end

  test "contiguous spans share the anchor they meet at" do
    graph = build(contiguous)

    assert_equal 3, ImportedNode.by_graph(graph.id).count, "three anchors for two spans, not four"
    arcs = ImportedArc.by_graph(graph.id).in_time_order.to_a
    assert_equal arcs[0].end_node_id, arcs[1].beg_node_id
  end

  test "an empty field is no label at all" do
    graph = build([ { beg: 0.0, end: 1.0, labels: { "Text" => "words", "Speaker" => "", "Section" => nil } } ])

    assert_equal [ "Text" ], ImportedLabel.by_graph(graph.id).pluck(:name)
  end

  test "a span missing either time isn't a span" do
    graph = build([ { beg: 0.0, end: nil, labels: { "Text" => "no end" } },
                    { beg: 1.0, end: 2.0, labels: { "Text" => "fine" } } ])

    assert_equal [ "fine" ], graph.transcript_rows.map { |r| r[:text] }
  end

  test "re-importing a tier replaces it rather than adding to it" do
    graph = build(contiguous)
    again = build([ { beg: 1.0, end: 2.0, labels: { "Text" => "only line" } } ])

    assert_equal graph.id, again.id, "same (docid, name) is the same graph"
    assert_equal 1, ImportedArc.by_graph(graph.id).count
    assert_equal 2, ImportedNode.by_graph(graph.id).count
    assert_equal 1, ImportedLabel.by_graph(graph.id).count
    assert_equal [ "only line" ], graph.transcript_rows.map { |r| r[:text] }
  end

  test "destroying a graph takes its rows with it" do
    graph = build(contiguous)
    build(contiguous, name: "asr")

    graph.destroy!

    assert_equal 0, ImportedNode.by_graph(graph.id).count
    assert_equal 0, ImportedArc.by_graph(graph.id).count
    assert_equal 0, ImportedLabel.by_graph(graph.id).count
    assert_equal 1, ImportedGraph.count, "and leaves the other tier alone"
    assert_equal 3, ImportedNode.count
  end

  test "remove_all takes the rows with the graphs, and only the ones selected" do
    build(contiguous)
    build(contiguous, name: "asr")
    keep = build(contiguous, docid: "other.wav")

    assert_equal 2, ImportedGraph.remove_all(ImportedGraph.for_docid(DOCID))

    assert_equal [ keep.id ], ImportedGraph.pluck(:id)
    assert_equal 3, ImportedNode.count, "only the kept graph's anchors are left"
    assert_equal 2, ImportedArc.count
    assert_equal 4, ImportedLabel.count
  end

  # A kit's source is a path to audio; an imported document id is whatever the
  # transcript called it. They meet at the stem, which is stored so a kit
  # opening doesn't scan every imported row to find its own.
  test "for_source matches a kit's audio however either side spells it" do
    graph = build(contiguous, docid: "AAA_passage")

    assert_equal "aaa_passage", graph.reload.stem
    [
      "AAA_passage", "AAA_passage.wav", "/audio/AAA_passage.wav",
      "/elsewhere/aaa_passage.flac", "AAA_passage.wav:A",
      # A kit's source is routinely a URL. Stripping the channel suffix must
      # not take the scheme with it — everything before the first colon of
      # "s3://bucket/AAA_passage.wav" is "s3".
      "s3://my-bucket/recordings/AAA_passage.wav",
      "s3://my-bucket/recordings/AAA_passage.wav:B",
      "https://example.org/audio/AAA_passage.flac"
    ].each do |source_uid|
      assert_equal graph.id, ImportedGraph.for_source(source_uid)&.id, "didn't match #{source_uid}"
    end
    assert_nil ImportedGraph.for_source("BBB_passage")
    assert_nil ImportedGraph.for_source(nil)
    assert_nil ImportedGraph.for_source("")
  end

  test "for_source reads the tier it is asked for" do
    build(contiguous, docid: "AAA", name: "reference")
    build([ { beg: 0.0, end: 1.0, labels: { "Text" => "asr guess" } } ], docid: "AAA", name: "asr")

    assert_equal [ "first", "second" ], ImportedGraph.for_source("/audio/AAA.wav").transcript_rows.map { |r| r[:text] }
    assert_equal [ "asr guess" ], ImportedGraph.for_source("/audio/AAA.wav", tier: "asr").transcript_rows.map { |r| r[:text] }
    assert_nil ImportedGraph.for_source("/audio/AAA.wav", tier: "alignment")
  end

  test "a re-import keeps the stem in step with the docid" do
    ImportedGraph.import_tsv_by_document(name: "reference", text: MULTI)

    assert_equal %w[ aaa_passage bbb_passage ], ImportedGraph.pluck(:stem).sort
  end

  test "one document holds several tiers, kept apart" do
    reference = build(contiguous, name: "reference")
    asr = build([ { beg: 0.4, end: 3.1, labels: { "Text" => "furst" } } ], name: "asr")

    assert_not_equal reference.id, asr.id
    assert_equal [ "first", "second" ], reference.transcript_rows.map { |r| r[:text] }
    assert_equal [ "furst" ], asr.transcript_rows.map { |r| r[:text] }
    assert_equal 2, ImportedGraph.for_docid(DOCID).count
  end

  test "transcript_rows flattens a span and its labels" do
    graph = build(contiguous)

    row = graph.transcript_rows.first
    assert_equal [ 0.5, 3.0, "first", "Alice" ], [ row[:beg], row[:end], row[:text], row[:speaker] ]
    assert_equal "", row[:section], "a field the file didn't carry reads as empty, never nil"
  end

  test "overlapping finds spans touching a stretch, not only those inside it" do
    graph = build(contiguous)

    assert_equal [ "first" ], graph.overlapping(2.0, 2.5).map { |r| r[:text] },
      "a span running past both edges still overlaps"
    assert_equal [ "first", "second" ], graph.overlapping(2.9, 3.1).map { |r| r[:text] }
    assert_equal [], graph.overlapping(7.0, 9.0).map { |r| r[:text] },
      "a span ending exactly at the start of the window doesn't overlap it"
  end

  test "graph_rows comes back in the projection's shape" do
    graph = build(contiguous)
    rows = graph.graph_rows

    assert_equal [ 0.5, 3.0, 7.0 ], rows[:nodes].map { |n| n[:time] }
    assert_equal [ 0.5, 3.0 ], rows[:arcs].map { |a| a[:beg] }
    assert_equal rows[:arcs].first[:id], rows[:labels].first[:arc_id]
    assert_equal rows[:nodes].first[:id], rows[:arcs].first[:beg_node_id]
  end

  test "the rows carry none of the annotator side's expansion" do
    graph = build(contiguous)
    arc = ImportedArc.by_graph(graph.id).first

    %w[ iid user_id task_id annotation_id tree_id ].each do |column|
      assert_not arc.respond_to?(column), "an imported arc has no #{column}"
    end
    assert_not ImportedNode.by_graph(graph.id).first.respond_to?(:docid),
      "the docid is one fact about the import, and lives on the graph"
  end

  test "import_tsv reads a headed Kit-style file and records where it came from" do
    text = [
      "Kit\tSource\tBegin\tEnd\tText\tSpeaker\tSection",
      "utt-1\ttest_tone\t0.5\t3.0\twrapper first segment\tAlice\tintro",
      "utt-2\ttest_tone\t4.0\t7.0\twrapper second segment\tBob\tbody"
    ].join("\n")

    graph = ImportedGraph.import_tsv(docid: DOCID, name: "reference", text: text, source: "/test_tone_10s.tsv")

    assert_equal "tsv", graph.format
    assert_equal "/test_tone_10s.tsv", graph.source
    assert graph.matches?(text), "the same bytes are a no-op re-import"
    assert_not graph.matches?(text + "\n#{"utt-3\tt\t8.0\t9.0\tmore"}")

    rows = graph.transcript_rows
    assert_equal [ "wrapper first segment", "wrapper second segment" ], rows.map { |r| r[:text] }
    assert_equal [ "Alice", "Bob" ], rows.map { |r| r[:speaker] }
    assert_equal [ "intro", "body" ], rows.map { |r| r[:section] }
    assert_equal [ [ 0.5, 3.0 ], [ 4.0, 7.0 ] ], rows.map { |r| [ r[:beg], r[:end] ] }
  end

  test "import_tsv reads the headerless layouts the way parse_tsv.js infers them" do
    kit_style = "utt-1\ttest_tone\t0.5\t3.0\tfrom kit style\tAlice"
    file_style = "a.wav\t0.5\t3.0\tfrom file style\tAlice"

    assert_equal [ "from kit style" ],
      ImportedGraph.import_tsv(docid: DOCID, name: "k", text: kit_style).transcript_rows.map { |r| r[:text] }
    assert_equal [ "from file style" ],
      ImportedGraph.import_tsv(docid: DOCID, name: "f", text: file_style).transcript_rows.map { |r| r[:text] }
  end

  test "import_tsv skips lines without real times, header repeats included" do
    text = [
      "file\tbeg\tend\ttext",
      "a.wav\t0.5\t3.0\tkept",
      "a.wav\t\t\tno times",
      "file\tbeg\tend\ttext",
      "",
      "a.wav\t4.0\t7.0\talso kept"
    ].join("\n")

    assert_equal [ "kept", "also kept" ],
      ImportedGraph.import_tsv(docid: DOCID, name: "reference", text: text).transcript_rows.map { |r| r[:text] }
  end

  # A file naming several documents is the normal case server-side, and the
  # damage from flattening them is silent: they all start near zero, so they
  # share anchors and every query crosses documents.
  MULTI = [
    "file\tbeg\tend\ttext",
    "AAA_passage\t0.0\t10.0\ta first",
    "AAA_passage\t10.0\t20.0\ta second",
    "BBB_passage\t0.0\t12.0\tb first"
  ].join("\n").freeze

  test "import_tsv refuses a file naming more than one document" do
    error = assert_raises(ImportedGraph::DocidError) do
      ImportedGraph.import_tsv(docid: DOCID, name: "reference", text: MULTI, source: "multi.tsv")
    end
    assert_match(/names 2 documents/, error.message)
    assert_equal 0, ImportedGraph.for_docid(DOCID).count, "and stores nothing"
  end

  test "import_tsv_by_document gives each document its own graph" do
    graphs = ImportedGraph.import_tsv_by_document(name: "reference", text: MULTI)

    assert_equal [ "AAA_passage", "BBB_passage" ], graphs.map(&:docid).sort
    a = ImportedGraph.for_docid("AAA_passage").named("reference").sole
    b = ImportedGraph.for_docid("BBB_passage").named("reference").sole
    assert_equal [ "a first", "a second" ], a.transcript_rows.map { |r| r[:text] }
    assert_equal [ "b first" ], b.transcript_rows.map { |r| r[:text] }
    assert_equal 3, ImportedNode.by_graph(a.id).count, "contiguous, so three anchors"
    assert_equal 2, ImportedNode.by_graph(b.id).count
    assert_equal [], a.overlapping(0.0, 1.0).map { |r| r[:text] } - [ "a first" ],
      "a query over one document doesn't reach the other"
  end

  test "the document column is read from either layout, and from this app's own export" do
    file_style = "file\tbeg\tend\ttext\na.wav\t0.0\t1.0\tone"
    kit_style = "Kit\tSource\tBegin\tEnd\tText\nutt-1\ta.wav\t0.0\t1.0\tone"
    exported = "Kit\tAudio\tBeg\tEnd\tText\nkit-9\ta.wav\t0.0\t1.0\tone"

    [ file_style, kit_style, exported ].each do |text|
      assert_equal [ "a.wav" ], ImportedGraph::TsvReader.rows(text).map { |r| r[:document] },
        "document not found in: #{text.lines.first.chomp}"
    end
  end

  test "headerless rows still name their document" do
    assert_equal [ "a.wav" ], ImportedGraph::TsvReader.rows("a.wav\t0.0\t1.0\tone").map { |r| r[:document] }
    assert_equal [ "src" ], ImportedGraph::TsvReader.rows("utt-1\tsrc\t0.0\t1.0\tone").map { |r| r[:document] }
  end

  test "Docid.template builds a docid out of each id" do
    resolve = ImportedGraph::Docid.template("/audio/%s.wav")
    assert_equal "/audio/AAA.wav", resolve.call("AAA")

    graphs = ImportedGraph.import_tsv_by_document(name: "reference", text: MULTI, resolve: resolve)
    assert_equal [ "/audio/AAA_passage.wav", "/audio/BBB_passage.wav" ], graphs.map(&:docid).sort
  end

  test "a stem keeps everything but the parts that vary" do
    {
      "s3://my-bucket/recordings/REC_passage_reading.wav" => "rec_passage_reading",
      "s3://my-bucket/recordings/REC_passage_reading.wav:C" => "rec_passage_reading",
      "/audio/REC.flac" => "rec",
      "REC" => "rec",
      "REC:A" => "rec",
      # Not a channel suffix: only a single A-D at the end is one.
      "REC:XY" => "rec:xy"
    }.each do |value, stem|
      assert_equal stem, ImportedGraph::Docid.stem(value), "stem of #{value}"
    end
  end

  test "Docid.match ignores the things that aren't predictable" do
    resolve = ImportedGraph::Docid.match([ "/audio/AAA_passage.wav", "/audio/BBB_passage.flac" ])

    assert_equal "/audio/AAA_passage.wav", resolve.call("AAA_passage"), "a missing extension"
    assert_equal "/audio/AAA_passage.wav", resolve.call("AAA_passage.wav"), "an extra one"
    assert_equal "/audio/AAA_passage.wav", resolve.call("/elsewhere/aaa_passage.mp3"), "a path, a case, another extension"
    assert_equal "/audio/AAA_passage.wav", resolve.call("AAA_passage:A"), "a channel suffix"
  end

  test "Docid.match refuses to guess" do
    resolve = ImportedGraph::Docid.match([ "/one/rec.wav", "/two/rec.flac" ])

    assert_match(/matches 2 known documents/, assert_raises(ImportedGraph::DocidError) { resolve.call("rec") }.message)
    assert_match(/matches no known document/, assert_raises(ImportedGraph::DocidError) { resolve.call("absent") }.message)
  end

  test "plan_tsv shows the mapping, failures included, without storing anything" do
    resolve = ImportedGraph::Docid.match([ "/audio/AAA_passage.wav" ])
    plan = ImportedGraph.plan_tsv(text: MULTI, resolve: resolve)

    assert_equal [ 2, 1 ], plan.map { |r| r[:spans] }
    assert_equal "/audio/AAA_passage.wav", plan.first[:docid]
    assert_match(/matches no known document/, plan.last[:docid])
    assert_equal 0, ImportedGraph.count
  end

  test "import_tsv sorts by time and rounds like the client does" do
    text = [ "a.wav\t4.0\t7.0\tsecond", "a.wav\t0.5004999\t3.0\tfirst" ].join("\n")

    rows = ImportedGraph.import_tsv(docid: DOCID, name: "reference", text: text).transcript_rows
    assert_equal [ "first", "second" ], rows.map { |r| r[:text] }
    assert_equal 0.5, rows.first[:beg], "three places, as round_to_3_places gives"
  end
end
