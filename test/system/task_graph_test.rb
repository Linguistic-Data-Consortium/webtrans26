require "application_system_test_case"

# The task graph page, driven for real: sign in, load
# /projects/:project_id/tasks/:id/graph, and check the SVG that comes out —
# a lane per kind of annotation, a rect per span, and the structure panel
# filling in when one is clicked.
#
# The controller test proves the rows are right. This proves they get drawn,
# which is the part a JSON assertion can't see.
class TaskGraphTest < ApplicationSystemTestCase
  class << self
    attr_accessor :vite_built
  end

  # Same real-Vite arrangement the dashboard tests use — the page is nothing
  # but a mount point, so the stub build would leave it empty.
  def self.ensure_vite_built!
    return if vite_built
    manifest = Rails.root.join("public/vite-test/.vite/manifest.json")
    unless manifest.exist?
      Bundler.with_unbundled_env do
        ok = system({ "RAILS_ENV" => "test" }, "bun", "run", "build", chdir: Rails.root.to_s)
        raise "vite build failed" unless ok
      end
    end
    self.vite_built = true
  end

  setup do
    self.class.ensure_vite_built!
    ViteStub.enabled = false

    Annotation.where(id: 0).first_or_create
    @alice = users(:alice)
    @alpha = projects(:alpha)
    @task  = tasks(:alpha_task_one)
    class_def = ClassDef.where(name: "ArcTranscription").first_or_create!
    root = NodeClass.where(name: "ArcTranscription:Root").first_or_create!(class_def: class_def)
    kit_type = KitType.create!(name: "sys-graph-#{SecureRandom.hex(3)}", node_class: root)

    @tree = Tree.create!(uid: "sys-graph-#{SecureRandom.hex(4)}", class_def: class_def, version: 2)
    # Three anchors, two segments, a section over both, and a comment on the
    # first — enough that every kind of lane has something in it.
    annotate("add", value: "10:NListItem,11:N")
    annotate("change", iid: 11, docid: "a.wav", begr: 0)
    annotate("add", value: "12:NListItem,13:N")
    annotate("change", iid: 13, docid: "a.wav", begr: 1.5)
    annotate("add", value: "14:NListItem,15:N")
    annotate("change", iid: 15, docid: "a.wav", begr: 4)
    annotate("add", value: "20:SegmentListItem,21:Arc,22:Text,23:Speaker")
    annotate("change", iid: 21, begi: 10, endi: 12)
    annotate("change", iid: 22, value: "hello there")
    annotate("change", iid: 23, value: "alice")
    annotate("add", value: "30:SegmentListItem,31:Arc,32:Text,33:Speaker")
    annotate("change", iid: 31, begi: 12, endi: 14)
    annotate("change", iid: 32, value: "how are you")
    annotate("change", iid: 33, value: "bob")
    annotate("add", value: "40:SectionListItem,41:Arc,42:Name")
    annotate("change", iid: 41, begi: 10, endi: 14)
    annotate("change", iid: 42, value: "intro")
    annotate("add", value: "50:CommentListItem,51:Arc,52:Comment")
    annotate("change", iid: 51, begi: 10, endi: 12)
    annotate("change", iid: 52, value: "noisy")

    @kit = Kit.create!(
      task_id: @task.id, kit_type_id: kit_type.id, tree_id: @tree.id,
      user_id: @alice.id, state: "assigned", source_uid: "a.wav",
      uid: "sys-graph-kit-#{SecureRandom.hex(4)}"
    )
  end

  teardown { ViteStub.enabled = true }

  # The lane checkboxes have no label text of their own — the swatch and the
  # name sit beside them inside the <label> — so reach the input through it.
  def uncheck_doc(docid)
    within(".max-h-56") { find("label", text: docid, exact_text: false).find("input").click }
  end
  alias_method :check_doc, :uncheck_doc

  # The picker starts on the first document, so a test wanting the whole task
  # has to ask for it.
  def show_all_documents
    find("button", text: /\ADocuments \(/).click
    click_on "All"
    click_on "Done"
  end

  def uncheck_lane(name)
    find("label", text: name).find("input[type=checkbox]").click
  end

  # A kit whose recording runs well past the opening window, so the initial
  # zoom is something other than the whole task.
  def long_kit(docid, seconds)
    tree = Tree.create!(uid: "sys-graph-#{SecureRandom.hex(4)}",
                        class_def: ClassDef.find_by(name: "ArcTranscription"), version: 2)
    was, @tree = @tree, tree
    annotate("add", value: "10:NListItem,11:N")
    annotate("change", iid: 11, docid: docid, begr: 0)
    annotate("add", value: "12:NListItem,13:N")
    annotate("change", iid: 13, docid: docid, begr: seconds)
    annotate("add", value: "20:SegmentListItem,21:Arc,22:Text,23:Speaker")
    annotate("change", iid: 21, begi: 10, endi: 12)
    annotate("change", iid: 22, value: "the long one")
    annotate("change", iid: 23, value: "dave")
    @tree = was
    Kit.create!(task_id: @task.id, kit_type_id: KitType.find_by(name: @kit.kit_type.name).id,
                tree_id: tree.id, user_id: @alice.id, state: "done", source_uid: docid,
                uid: "sys-graph-kit-#{SecureRandom.hex(4)}")
  end

  # Another kit. Pass a docid already in use to put two kits on one document.
  def another_kit(docid, text: nil, speaker: "carol")
    tree = Tree.create!(uid: "sys-graph-#{SecureRandom.hex(4)}",
                        class_def: ClassDef.find_by(name: "ArcTranscription"), version: 2)
    was, @tree = @tree, tree
    annotate("add", value: "10:NListItem,11:N")
    annotate("change", iid: 11, docid: docid, begr: 0)
    annotate("add", value: "12:NListItem,13:N")
    annotate("change", iid: 13, docid: docid, begr: 3)
    annotate("add", value: "20:SegmentListItem,21:Arc,22:Text,23:Speaker")
    annotate("change", iid: 21, begi: 10, endi: 12)
    annotate("change", iid: 22, value: text || "line in #{docid}")
    annotate("change", iid: 23, value: speaker)
    @tree = was
    Kit.create!(task_id: @task.id, kit_type_id: KitType.find_by(name: @kit.kit_type.name).id,
                tree_id: tree.id, user_id: @alice.id, state: "done", source_uid: docid,
                uid: "sys-graph-kit-#{SecureRandom.hex(4)}")
  end

  def annotate(message, **attributes)
    Annotation.create!(
      { tree_id: @tree.id, task_id: @task.id, user_id: @alice.id, message: message, last_iid: "0" }
        .merge(attributes)
    )
  end

  def sign_in_and_open
    visit new_session_url
    fill_in "email_address", with: @alice.email_address
    fill_in "password", with: "password123"
    click_on "Sign in"
    # Wait for the sign-in redirect to land before navigating again. Without
    # this, Capybara issues the next visit while the redirect is still in
    # flight and the dashboard arrives on top of the page we asked for.
    assert_current_path(/\/users\/\d+/, wait: 10)

    visit graph_project_task_url(project_id: @alpha.id, id: @task.id)
    assert_text "annotation graph", wait: 10
  end

  test "the page draws a lane per kind of annotation and a span per arc" do
    sign_in_and_open

    # The header counts what was snapshotted: 3 anchors, 4 spans, 6 labels.
    assert_text "3 anchors, 4 spans, 6 labels", wait: 10

    # A lane per (arc name, label name), discovered from the data — including
    # the comment group, which nothing on the server knows about.
    [ "Segment · Text", "Segment · Speaker", "Section · Name", "Comment · Comment" ].each do |lane|
      assert_selector "label", text: lane
    end

    # And the spans themselves, drawn as text inside their rects.
    assert_selector "svg text", text: "hello there"
    assert_selector "svg text", text: "how are you"
    assert_selector "svg text", text: "intro"
    assert_selector "svg text", text: "noisy"
  end

  test "a span's label is centred when it fits, and readable from the left when it doesn't" do
    sign_in_and_open

    # "alice" is short enough for its span, so it sits in the middle of it.
    speaker = find("svg text", exact_text: "alice")
    rect = speaker.sibling("rect")
    middle = rect.evaluate_script("this.x.baseVal.value + this.width.baseVal.value / 2")
    assert_equal "middle", speaker.evaluate_script("this.getAttribute('text-anchor')")
    assert_in_delta middle, speaker.evaluate_script("this.x.baseVal[0].value"), 1

    # A label wider than its span is left alone: centring it would let the clip
    # take a bite off each end and leave the middle of a word.
    # Long enough to overflow even with the structure pane shut and the drawing
    # at full width — the span it sits in is three seconds of a ten second window.
    another_kit("a.wav", text: "a considerably longer line than the span it sits in, " \
                               "going well past the width of three seconds of this window")
    long_kit("long.wav", 40) # so the opening window is a real ten seconds
    visit graph_project_task_url(project_id: @alpha.id, id: @task.id)
    assert_text "annotation graph", wait: 10

    long = find("svg text", text: "a considerably longer")
    assert_equal "start", long.evaluate_script("this.getAttribute('text-anchor')")
    assert_operator long.evaluate_script("this.getComputedTextLength()"), :>,
                    long.sibling("rect").evaluate_script("this.width.baseVal.value"),
                    "the label has to actually overflow for this to be the case under test"
  end

  test "a label scrolls with its span rather than sliding to stay on screen" do
    # The reported bug: the label was placed off the clamped box, so a span
    # running off the left edge kept its text in the middle of whatever was
    # still visible — the text appeared to stand still while its span moved.
    #
    # Measured against a span that stays fully on screen, whose rect therefore
    # moves by exactly the pan distance. The clipped span's label has to move by
    # the same amount, because it is pinned to times, not to what's visible.
    long_kit("long.wav", 40) # so the opening window is a real ten seconds
    sign_in_and_open

    moving = -> { find("svg text", text: "how are you").sibling("rect").evaluate_script("this.x.baseVal.value") }
    clipped = -> { find("svg text", text: "hello there").evaluate_script("this.x.baseVal[0].value") }

    reference_before, label_before = moving.call, clipped.call

    # One press pans a tenth of the window — a second, which leaves "hello
    # there" (0 to 1.5s) half off the left edge while "how are you" (1.5 to 4s)
    # stays wholly on it. Two presses and the first is gone from the drawing.
    find("[data-testid='position-thumb']").send_keys(:arrow_right)
    sleep 0.3

    shift = reference_before - moving.call
    assert_operator shift, :>, 20, "the pan should have moved the drawing a visible distance"
    assert_in_delta shift, label_before - clipped.call, 2,
                    "the label should have travelled with its span, not re-centred in what's left"
  end

  test "unchecking a lane takes it out of the drawing" do
    sign_in_and_open
    # exact_text, because the kit's header names its annotator — who is also
    # the speaker on the first segment.
    assert_selector "svg text", exact_text: "alice"

    uncheck_lane "Segment · Speaker"
    assert_no_selector "svg text", exact_text: "alice"
    assert_no_selector "svg text", exact_text: "bob"
    # The other lanes are untouched.
    assert_selector "svg text", text: "hello there"
    assert_selector "svg text", text: "intro"
  end

  test "the structure pane is shut until a span is clicked, and the plot is wider for it" do
    sign_in_and_open
    assert_no_selector "div", text: "Sharing an anchor"
    shut = find(".overflow-y-auto").evaluate_script("this.clientWidth")

    find("svg text", text: "hello there").sibling("rect").click
    assert_text "Sharing an anchor"
    open_width = find(".overflow-y-auto").evaluate_script("this.clientWidth")
    assert_operator shut, :>, open_width, "the drawing should have been wider with the pane shut"

    click_on "Close"
    assert_no_text "Sharing an anchor"
    assert_equal shut, find(".overflow-y-auto").evaluate_script("this.clientWidth")
  end

  test "the Structure button opens and shuts the pane on its own" do
    sign_in_and_open
    click_on "Structure"
    assert_text "Click a span to see its anchors"
    click_on "Close"
    assert_no_text "Click a span to see its anchors"
  end

  test "a span's tooltip says which kit and who annotated it, and no more" do
    another_kit("a.wav", text: "second pass", speaker: "carol")
    sign_in_and_open

    # Two passes over one recording share a lane, so which kit a span belongs
    # to is the thing the drawing can no longer show on its own.
    second = Kit.order(:id).last
    assert_equal "kit #{@kit.id}/#{@kit.uid} · #{@alice.name}",
                 find("svg text", text: "hello there").sibling("title", visible: :all).text(:all)
    assert_equal "kit #{second.id}/#{second.uid} · #{@alice.name}",
                 find("svg text", text: "second pass").sibling("title", visible: :all).text(:all)
  end

  test "clicking a span fills the structure panel with its anchors and labels" do
    sign_in_and_open
    # The pane is shut until a span is clicked — the drawing gets the width.
    assert_no_text "Sharing an anchor"

    # The rect is the click target, not the label over it.
    find("svg text", text: "hello there").sibling("rect").click

    # Its own row: the list item's iid, and the Arc child, which is a different
    # node — the pair ARCHITECTURE.md warns are easy to confuse.
    assert_text "20 (SegmentListItem)"
    assert_text "arc_node_iid"
    # Its labels, and the spans sharing an anchor with it: the next segment,
    # the section over both, and the comment on the same stretch.
    assert_text "hello there"
    assert_text "Sharing an anchor (3)"
  end

  # ── reusing a snapshot ────────────────────────────────────────────────────

  test "a plain load doesn't claim to be snapshotting" do
    # It replays only the kits annotated since their rows were written, which is
    # usually none of them. Saying "snapshotting every kit" while that goes on
    # claims work that mostly isn't happening.
    sign_in_and_open
    assert_no_text "Re-snapshotting every kit"
  end

  test "Re-snapshot says what it is doing, because it really does do them all" do
    sign_in_and_open
    visit graph_project_task_url(project_id: @alpha.id, id: @task.id)
    assert_text "already up to date", wait: 10

    click_on "Re-snapshot"
    assert_text "snapshotted in", wait: 10
  end

  test "a revisit reuses the rows and says so" do
    sign_in_and_open
    assert_text "snapshotted in", wait: 10
    written = GraphArc.by_tree(@kit.tree_id).maximum(:created_at)

    visit graph_project_task_url(project_id: @alpha.id, id: @task.id)
    assert_text "already up to date", wait: 10
    assert_equal written, GraphArc.by_tree(@kit.tree_id).maximum(:created_at)
  end

  test "Re-snapshot replays even when nothing has changed" do
    sign_in_and_open
    visit graph_project_task_url(project_id: @alpha.id, id: @task.id)
    assert_text "already up to date", wait: 10
    written = GraphArc.by_tree(@kit.tree_id).maximum(:created_at)

    click_on "Re-snapshot"
    assert_text "snapshotted in", wait: 10
    assert_operator GraphArc.by_tree(@kit.tree_id).maximum(:created_at), :>, written
  end

  test "a mixed task says how many it had to redo" do
    another_kit("b.wav")
    sign_in_and_open
    assert_text "snapshotted in", wait: 10

    another_kit("c.wav") # new kit, never snapshotted
    visit graph_project_task_url(project_id: @alpha.id, id: @task.id)
    assert_text "1 re-snapshotted, 2 already current", wait: 10
  end

  # ── the opening window ────────────────────────────────────────────────────

  test "the page opens on ten seconds, not the whole task" do
    # A whole task at once is a shape, not a transcript: a segment is a few
    # pixels and none of the text fits.
    long_kit("long.wav", 40)
    sign_in_and_open
    assert_text "0s – 10s", wait: 10
    assert_text "(4.0×)" # forty seconds of task in a ten second window
  end

  test "Fit still gives the whole task" do
    long_kit("long.wav", 40)
    sign_in_and_open
    assert_text "0s – 10s", wait: 10

    click_on "Fit"
    assert_text "0s – 40s"
    assert_text "(1.0×)"
  end

  test "a task shorter than the opening window shows all of itself" do
    # The fixture kit runs to 4s, so there is nothing past the window to reach.
    sign_in_and_open
    assert_text "0s – 4s", wait: 10
    assert_button "→", disabled: true
  end

  test "opening zoomed in still leaves somewhere to pan" do
    long_kit("long.wav", 40)
    sign_in_and_open
    assert_button "←", disabled: true  # at the start
    assert_button "→", disabled: false # with most of the task ahead

    click_on "⇥"
    assert_text "30s – 40s"
  end

  # ── documents ─────────────────────────────────────────────────────────────

  test "kits over one recording are drawn on one set of lanes" do
    # Two passes over a.wav — the kit from setup and this one. They used to be
    # two blocks down the page with a full set of lanes each.
    another_kit("a.wav", text: "second pass", speaker: "carol")
    sign_in_and_open

    assert_text "2 of 2 kits over 1 document", wait: 10
    # One header per document, not per kit.
    assert_selector "svg text", exact_text: "▾ a.wav"
    assert_no_selector "svg text", text: "▾ extra"
    # Both passes are drawn, and both are in the same Text lane.
    assert_selector "svg text", text: "hello there"
    assert_selector "svg text", text: "second pass"
    assert_equal 1, all("svg text", text: "Segment · Text").length
  end

  test "a document header names the kits under it, by id and uid" do
    another_kit("a.wav", text: "second pass")
    sign_in_and_open
    # Either identity alone sends you looking the other up: the integer is what
    # the tasks pages use, the hex uid is what the tool and the URLs use.
    header = find("svg text", text: "2 kits (", wait: 10)
    assert_includes header.find("title", visible: :all).text(:all),
                    "#{@kit.id}/#{@kit.uid}"
  end

  test "the structure panel names the kit by id and uid too" do
    sign_in_and_open
    find("svg text", text: "hello there").sibling("rect").click
    assert_text "#{@kit.id}/#{@kit.uid}"
  end

  test "a span in a shared document still belongs to its own kit" do
    # The merge is a drawing: the two kits keep their own trees, so a span's
    # neighbours are the ones inside its own kit however the times line up.
    another_kit("a.wav", text: "second pass")
    sign_in_and_open

    find("svg text", text: "second pass").sibling("rect").click
    assert_text "Sharing an anchor (0)"
    # And the panel names the kit it came from, not the document.
    assert_text "20 (SegmentListItem)"
  end

  test "it opens on the first document alone, not all of them" do
    # A task is routinely dozens of recordings, and all of them at once is a
    # wall. The picker says which, and how many there are to go back for.
    another_kit("b.wav")
    another_kit("c.wav")
    sign_in_and_open
    assert_text "Documents (1/3)", wait: 10

    assert_selector "svg text", exact_text: "▾ a.wav"
    assert_no_selector "svg text", exact_text: "▾ b.wav"
    assert_no_selector "svg text", exact_text: "▾ c.wav"
    # The header still counts the whole task — it says what was snapshotted.
    assert_text "3 of 3 kits over 3 documents"
  end

  test "a document is named by the end of its docid, not the whole path" do
    # Real docids are S3 keys and URLs; the part that tells two apart is at the
    # end, and the rest is the same for every document in the task.
    # Explicit text, or the segment label would carry the path into the drawing
    # and the assertion below couldn't tell the two apart.
    another_kit("s3://my-bucket/recordings/reading.wav", text: "a line")
    sign_in_and_open
    show_all_documents

    assert_selector "svg text", text: "▾ reading.wav"
    assert_no_selector "svg text", text: "my-bucket"

    find("button", text: /\ADocuments \(/).click
    within(".max-h-56") do
      assert_selector "label", text: "reading.wav"
      assert_no_selector "label", text: "my-bucket"
      # The whole docid is still there to hover for.
      assert_equal "s3://my-bucket/recordings/reading.wav",
                   find("label", text: "reading.wav")[:title]
    end
  end

  test "two documents whose paths end alike keep enough of them to tell apart" do
    another_kit("s3://c/sessionA/take1.wav", text: "a line")
    another_kit("s3://c/sessionB/take1.wav", text: "another line")
    sign_in_and_open
    show_all_documents

    assert_selector "svg text", text: "▾ sessionA/take1.wav"
    assert_selector "svg text", text: "▾ sessionB/take1.wav"
  end

  test "the document picker draws only what is ticked" do
    another_kit("b.wav")
    another_kit("c.wav")
    sign_in_and_open
    assert_text "Documents (1/3)", wait: 10

    click_on "Documents (1/3)"
    check_doc "b.wav"
    assert_text "Documents (2/3)"
    assert_selector "svg text", exact_text: "▾ b.wav"
    assert_no_selector "svg text", exact_text: "▾ c.wav"

    uncheck_doc "b.wav"
    assert_text "Documents (1/3)"
    assert_no_selector "svg text", exact_text: "▾ b.wav"

    click_on "All"
    assert_text "Documents (3/3)"
    assert_selector "svg text", exact_text: "▾ b.wav"
    assert_selector "svg text", exact_text: "▾ c.wav"
  end

  test "the picker searches, and Only these keeps just the matches" do
    another_kit("b.wav")
    another_kit("interview_1.wav")
    another_kit("interview_2.wav")
    sign_in_and_open

    click_on "Documents (1/4)"
    fill_in "search documents", with: "interview"
    assert_selector "label", text: "interview_1.wav"
    assert_no_selector "label", text: "b.wav"

    click_on "Only these"
    assert_text "Documents (2/4)"
    assert_selector "svg text", exact_text: "▾ interview_1.wav"
    assert_no_selector "svg text", exact_text: "▾ a.wav"
  end

  test "unticking the last document leaves nothing drawn, and says so" do
    # Unticking used to tick everything else instead, because an empty set meant
    # "all of them". Nothing ticked is a real answer now.
    another_kit("b.wav")
    sign_in_and_open
    click_on "Documents (1/2)"

    uncheck_doc "a.wav"
    assert_text "Documents (0/2)"
    assert_no_selector "svg text", exact_text: "▾ a.wav"
    assert_no_selector "svg text", exact_text: "▾ b.wav"
    assert_text "No document is ticked"

    # And the other boxes stayed unticked rather than filling in.
    within(".max-h-56") { assert_equal 0, all("input[type=checkbox]").count(&:checked?) }
  end

  test "None clears the lot, All brings it back" do
    another_kit("b.wav")
    another_kit("c.wav")
    sign_in_and_open
    click_on "Documents (1/3)"

    click_on "All"
    assert_text "Documents (3/3)"
    click_on "None"
    assert_text "Documents (0/3)"
    assert_text "No document is ticked"

    click_on "All"
    assert_text "Documents (3/3)"
    assert_no_text "No document is ticked"
  end

  # ── the scroller ──────────────────────────────────────────────────────────

  test "an ordinary wheel over the plot scrolls the kits" do
    # This was broken: the plot called preventDefault on every wheel event in
    # order to pan, which swallowed the vertical scroll and left every kit past
    # the first screen unreachable by wheel.
    12.times { |i| another_kit("extra_#{i}.wav") }
    sign_in_and_open
    show_all_documents
    assert_selector "svg text", text: "line in extra_0.wav", wait: 10

    scroller = find(".overflow-y-auto")
    assert scroller.evaluate_script("this.scrollHeight > this.clientHeight + 4"),
           "the drawing should be taller than its container, or there is nothing to prove"

    wheel_over plot_element, 0, 400
    assert scroller.evaluate_script("this.scrollTop") > 0,
           "a wheel over the plot should have scrolled the kits"
  end

  test "the plot does not take the wheel at all any more" do
    # Nothing on the drawing listens for it: the window is moved and sized by
    # the two bars, and the wheel belongs to the browser. A cancelled wheel is
    # one the container could no longer scroll on, so none may be cancelled.
    sign_in_and_open
    assert_equal false, wheel_cancelled?(deltaY: 300)
    assert_equal false, wheel_cancelled?(deltaY: 300, ctrlKey: true)
    assert_equal false, wheel_cancelled?(deltaY: 300, shiftKey: true)
    assert_equal false, wheel_cancelled?(deltaX: 300)
  end

  test "a sideways wheel leaves the window where it was" do
    long_kit("long.wav", 40)
    sign_in_and_open
    before = window_text

    wheel_over plot_element, 300, 0
    sleep 0.3
    assert_equal before, window_text

    wheel_over plot_element, 0, 300, shift: true
    sleep 0.3
    assert_equal before, window_text
  end

  test "the ruler stays put while the kits scroll under it" do
    12.times { |i| another_kit("extra_#{i}.wav") }
    sign_in_and_open
    show_all_documents

    scroller = find(".overflow-y-auto")
    wheel_over plot_element, 0, 400
    assert scroller.evaluate_script("this.scrollTop") > 0

    # The ruler is a sibling of the scroller, not the top of the drawing, so
    # the times are still on screen after scrolling down.
    assert_selector "svg[aria-hidden='true'] text", text: "0s"
    assert_equal 0, find("svg[aria-hidden='true']").evaluate_script(
      "this.closest('.overflow-y-auto') ? 1 : 0"
    )
  end

  # ── moving the window ─────────────────────────────────────────────────────

  test "the pan buttons move the window and go flat at the ends" do
    sign_in_and_open
    # Fit is the whole task, so there is nowhere to pan yet.
    assert_button "→", disabled: true
    assert_button "⇤", disabled: true

    # Zooming works on the centre of the window, so this lands in the middle of
    # the task with somewhere to go in both directions.
    click_on "+"
    assert_button "→", disabled: false
    assert_button "←", disabled: false

    middle = window_text
    click_on "→"
    assert_no_text middle, wait: 5
  end

  test "the end buttons jump the whole way" do
    sign_in_and_open
    click_on "+"

    click_on "⇥"
    assert_button "→", disabled: true
    assert_button "⇥", disabled: true

    click_on "⇤"
    assert_button "←", disabled: true
    assert_button "⇤", disabled: true
  end

  test "panning keeps the zoom level it was given" do
    sign_in_and_open
    click_on "+"
    zoom = window_text[/\(([\d.]+)×\)/, 1]

    click_on "→"
    assert_equal zoom, window_text[/\(([\d.]+)×\)/, 1]
  end

  test "dragging the plot does not pan it" do
    # Panning is buttons now: a drag fought the click that selects a span, and
    # there was nowhere on the plot to grab that wasn't already something.
    sign_in_and_open
    click_on "+"
    before = window_text

    page.driver.browser.action
      .click_and_hold(plot_element.native).move_by(-250, 0).release.perform

    assert_equal before, window_text
  end

  # ── the two bars ──────────────────────────────────────────────────────────

  test "the position thumb is as wide a share of its track as the window is of the task" do
    long_kit("long.wav", 40) # opens on ten seconds, a quarter of the task
    sign_in_and_open

    track = find("[data-testid='position-bar']")
    thumb = find("[data-testid='position-thumb']")
    share = thumb.evaluate_script("this.offsetWidth") /
            track.evaluate_script("this.clientWidth").to_f
    assert_in_delta 0.25, share, 0.03
  end

  test "the position bar sits above the ruler, not below the kits" do
    long_kit("long.wav", 40)
    sign_in_and_open

    bar = find("[data-testid='position-bar']").evaluate_script("this.getBoundingClientRect().top")
    ruler = find("svg[aria-hidden='true']").evaluate_script("this.getBoundingClientRect().top")
    assert_operator bar, :<, ruler, "the position bar should be above the ruler"
  end

  test "dragging the position thumb moves the window along the recording" do
    long_kit("long.wav", 40)
    sign_in_and_open
    assert_text "0s – 10s", wait: 10

    drag_thumb_to "position-thumb", "position-bar", 1.0
    assert_text "30s – 40s"

    drag_thumb_to "position-thumb", "position-bar", 0.0
    assert_text "0s – 10s"
  end

  test "dragging the position thumb keeps the zoom it was given" do
    long_kit("long.wav", 40)
    sign_in_and_open
    zoom = window_text[/\(([\d.]+)×\)/, 1]

    drag_thumb_by "position-thumb", 120
    assert_equal zoom, window_text[/\(([\d.]+)×\)/, 1]
  end

  test "dragging the zoom thumb changes how much is on screen" do
    long_kit("long.wav", 40)
    sign_in_and_open
    assert_text "0s – 10s", wait: 10

    drag_thumb_to "zoom-thumb", "zoom-bar", 0.0 # all the way out
    assert_text "0s – 40s"
    assert_text "(1.0×)"
  end

  test "zooming out with the bar fills the position track and pins its thumb" do
    long_kit("long.wav", 40)
    sign_in_and_open
    drag_thumb_to "zoom-thumb", "zoom-bar", 0.0

    track = find("[data-testid='position-bar']")
    thumb = find("[data-testid='position-thumb']")
    assert_in_delta track.evaluate_script("this.clientWidth"),
                    thumb.evaluate_script("this.offsetWidth"), 2
  end

  test "the bars answer the arrow keys" do
    long_kit("long.wav", 40)
    sign_in_and_open
    assert_text "0s – 10s", wait: 10

    find("[data-testid='position-thumb']").send_keys(:arrow_right)
    assert_no_text "0s – 10s", wait: 5

    zoom = window_text[/\(([\d.]+)×\)/, 1]
    find("[data-testid='zoom-thumb']").send_keys(:arrow_left)
    assert_not_equal zoom, window_text[/\(([\d.]+)×\)/, 1]
  end

  test "a kit with nothing annotated says so rather than drawing an empty frame" do
    Kit.where(task_id: @task.id).destroy_all
    sign_in_and_open
    assert_text "No kit in this task has been annotated yet"
  end

  # Pointer-drag a bar's thumb by `dx` pixels — real pointer events, which is
  # what the thumbs listen for. For small nudges; a large dx walks the pointer
  # off the viewport and Selenium refuses.
  def drag_thumb_by(testid, dx)
    thumb = find("[data-testid='#{testid}']")
    page.driver.browser.action
      .click_and_hold(thumb.native).move_by(dx, 0).release.perform
    sleep 0.3
  end

  # Drag the thumb to a fraction along its own track. Expressed as a move *to*
  # a point inside the track rather than a distance, so it lands exactly at the
  # end without the pointer ever leaving the window.
  def drag_thumb_to(thumb_testid, bar_testid, fraction)
    thumb = find("[data-testid='#{thumb_testid}']")
    bar   = find("[data-testid='#{bar_testid}']")
    width = bar.evaluate_script("this.clientWidth")
    offset = ((fraction - 0.5) * width).round
    page.driver.browser.action
      .click_and_hold(thumb.native)
      .move_to(bar.native, offset, 0)
      .release.perform
    sleep 0.3
  end

  def window_text
    find("span.tabular-nums").text
  end

  def plot_element
    find("svg[role='application']")
  end

  # A real, trusted wheel over the element — Selenium's own wheel input, not a
  # dispatched WheelEvent. A synthetic one never performs the browser's default
  # action, so it could not tell a scrolling page from a blocked one.
  def wheel_over(element, dx, dy, shift: false)
    origin = Selenium::WebDriver::WheelActions::ScrollOrigin.element(element.native)
    action = page.driver.browser.action
    action = action.key_down(:shift) if shift
    action = action.scroll_from(origin, dx, dy)
    action = action.key_up(:shift) if shift
    action.perform
  end

  # Whether the plot's own handler cancels a wheel — a cancelled event is one
  # the container can no longer scroll on.
  def wheel_cancelled?(**init)
    page.evaluate_script(<<~JS, init.transform_keys(&:to_s))
      (function (init) {
        const e = new WheelEvent('wheel', Object.assign({ bubbles: true, cancelable: true }, init));
        document.querySelector("svg[role='application']").dispatchEvent(e);
        return e.defaultPrevented;
      })(arguments[0]);
    JS
  end
end
