#!/usr/bin/env ruby
# The transcribe_text_only mode, driven end to end.
#
# A kit type carrying the `transcribe_text_only` constraint transcribes against
# an imported graph rather than against nothing: the tool finds the graph whose
# document matches its audio, shows each span as a caption, creates a segment
# per span when the kit is still empty, and from then on allows nothing but
# typing. This drives that in a real browser and then reads the annotation log
# to check the tool wrote only what the mode permits.
#
#   1. Start the repl server in another terminal:
#         bin/repl
#
#   2. Run this script:
#         bundle exec ruby script/transcription_auto_text_only.rb
#
# Exit codes: 0 = PASS, 1 = FAIL.

ENV["RAILS_ENV"] ||= "repl"

require_relative "transcription_repl_lib"

TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

WAV = TranscriptionReplLib::WAV_PATH
TSV = File.expand_path("../public/test_tone_10s.tsv", __dir__)

# public/test_tone_10s.tsv, which is what gets imported below. Speaker and
# section are in the file and deliberately don't reach the transcript: this
# mode takes the spans and their text, and the annotator may set neither.
EXPECTED = [
  { beg: 0.5, end: 3.0, text: "wrapper first segment" },
  { beg: 4.0, end: 7.0, text: "wrapper second segment" }
].freeze

TYPED = "typed into the first span".freeze

puts "==> Setting up data (transcribe_text_only kit)..."
ctx = TranscriptionReplLib.setup_data(
  source_uid: WAV,
  source_filename: "test_tone_10s.wav",
  kit_type_name: "transcription_repl_text_only",
  name_suffix: "_text_only",
  # Comments are their own permission: a kit locked to typing can still carry
  # a remark about a stretch of audio, and this checks the two combine.
  extra_constraints: { "transcribe_text_only" => "transcribe_text_only", "comments" => "comments" }
)

# The imported graph the kit will find. Its document id is spelled without the
# directory or the extension the kit's source carries — matching on the stem is
# the point.
puts "==> Importing the reference graph..."
graph = ImportedGraph.import_tsv(docid: "test_tone_10s", name: "reference", text: File.read(TSV), source: TSV)
puts "  -> #{graph.docid} '#{graph.name}': #{graph.transcript_rows.size} spans, stem=#{graph.stem}"
raise "the kit's audio doesn't find that graph" unless ImportedGraph.for_source(WAV)&.id == graph.id

puts ""
puts "==> Launching Chrome..."
driver = TranscriptionReplLib.launch_browser_signed_in(
  user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task]
)
at_exit { driver.quit rescue nil }
wait = Selenium::WebDriver::Wait.new(timeout: 30)

passes = []
failures = []
check = ->(label, ok) { (ok ? passes : failures) << label }

puts "==> Waiting for the transcription tool to mount..."
wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }

guide_close = driver.find_elements(css: "[aria-label='Close guide']").find(&:displayed?)
if guide_close
  guide_close.click
  wait.until { driver.find_elements(css: "[aria-label='Close guide']").none?(&:displayed?) }
end

segment_count = -> { driver.find_elements(css: "#segments .segment").length }
rows_now = lambda do
  driver.execute_script(<<~JS)
    return Array.from(document.querySelectorAll('#segments .segment')).map(function (el) {
      const ta = el.querySelector('textarea.ann-segment');
      const div = el.querySelector('.transcript');
      const spk = el.querySelector('.speaker');
      return {
        text: ((ta && ta.value) || (div && div.textContent) || '').trim(),
        speaker: (spk ? spk.textContent : '').trim(),
        beg: (el.querySelector('.btime') || {}).textContent,
        end: (el.querySelector('.etime') || {}).textContent
      };
    });
  JS
end

# ── the spans become segments ─────────────────────────────────────────────
puts ""
puts "==> The imported spans should have become segments..."
seeded =
  begin
    wait.until { segment_count.call == EXPECTED.length }
    true
  rescue Selenium::WebDriver::Error::TimeoutError
    false
  end
check.call("a segment per imported span (#{EXPECTED.length}; got #{segment_count.call})", seeded)

check.call("the tool locked itself to text only", driver.execute_script("return !!(window.ldc && window.ldc.text_only)"))

initial = rows_now.call
check.call("the segments start empty — the text is the annotator's to type",
           initial.all? { |r| r["text"].to_s.empty? })
check.call("no speaker came across from the file",
           initial.all? { |r| r["speaker"].to_s.empty? || r["speaker"].to_s == "empty" })

graph_spans = driver.execute_script("return (window.ldc.graph.arcs || []).map(a => [a.beg_iid, a.end_iid]).length")
times = driver.execute_script(<<~JS)
  const g = window.ldc.graph, t = new Map(g.nodes.map(n => [n.iid, Number(n.time)]));
  return g.arcs.filter(a => a.name === 'SegmentListItem')
    .map(a => [t.get(a.beg_iid), t.get(a.end_iid)])
    .sort((x, y) => x[0] - y[0]);
JS
check.call("the segments sit at the imported times (#{times.inspect})",
           times == EXPECTED.map { |e| [ e[:beg], e[:end] ] })

captions = driver.execute_script(
  "return Array.from(document.querySelectorAll('#segments .reference-text')).map(e => e.textContent.trim());"
)
EXPECTED.each do |exp|
  check.call("#{exp[:text].inspect} is shown as a caption over its segment",
             captions.any? { |c| c.include?(exp[:text]) })
end

# The line the annotator types into is plain: the ch1..ch4 tint is there to
# tell two channels apart, and an imported transcript is one document.
tinted = driver.execute_script(<<~JS)
  return Array.from(document.querySelectorAll('#segments .segment'))
    .filter(el => /\\bch[1-4]\\b/.test(el.className)).length;
JS
check.call("the empty lines carry no channel tint (#{tinted} tinted)", tinted.to_i.zero?)

# …and a rule separates each prompt-and-line pair from the one before it.
ruled = driver.execute_script(<<~JS)
  return Array.from(document.querySelectorAll('#segments .reference-text'))
    .map(el => /\\bborder-t\\b/.test(el.className));
JS
check.call("a rule separates the pairs, but not above the first (#{ruled.inspect})",
           ruled.length == EXPECTED.length && ruled.first == false && ruled.drop(1).all?)

# ── what the annotator may do: type ────────────────────────────────────────
puts "==> Typing into the first segment..."
driver.find_elements(css: "#segments .segment").first.click
textarea = wait.until { driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment") }
textarea.send_keys(TYPED)
textarea.send_keys(:tab)
sleep 0.6

check.call("the typed text reached the transcript",
           rows_now.call.any? { |r| r["text"].to_s.include?(TYPED) })
check.call("…and was written to the annotation log",
           Annotation.where(kit_id: ctx[:kit].id).pluck(:value).compact.any? { |v| v.to_s.include?(TYPED) })

# ── what it may not do ────────────────────────────────────────────────────
puts "==> The prohibited gestures should do nothing..."
keyboard = driver.find_element(css: ".keyboard")

# Split the active segment at the cursor.
driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", 1.0, 0.5)
keyboard.click
keyboard.send_keys(",")
sleep 0.5
check.call("',' didn't split a segment (still #{segment_count.call})", segment_count.call == EXPECTED.length)

# Merge with the following segment.
keyboard.click
keyboard.send_keys("m")
sleep 0.5
check.call("'m' didn't merge two segments (still #{segment_count.call})", segment_count.call == EXPECTED.length)

# Create a segment from a selection, in empty audio well clear of the spans.
driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", 8.0, 1.0)
sleep 0.2
keyboard.click
keyboard.send_keys(:enter)
sleep 0.8
check.call("enter on a selection didn't create a segment (still #{segment_count.call})",
           segment_count.call == EXPECTED.length)

# Delete the active line. ctrl+d arms a confirm button, which shouldn't appear.
driver.find_elements(css: "#segments .segment").first.click
sleep 0.2
driver.execute_script(<<~JS)
  const ta = document.querySelector('#segments .segment.active-segment textarea.ann-segment');
  if (ta) {
    ta.focus();
    ta.dispatchEvent(new KeyboardEvent('keydown', {
      key: 'd', code: 'KeyD', ctrlKey: true, bubbles: true, cancelable: true
    }));
  }
JS
sleep 0.5
delete_button = driver.find_elements(xpath: "//button[normalize-space()='delete']").select(&:displayed?)
check.call("ctrl+d didn't offer a delete button", delete_button.empty?)
check.call("…and nothing was deleted (still #{segment_count.call})", segment_count.call == EXPECTED.length)

# ── comments: allowed here, and no part of the transcript ─────────────────
# The transcript's shape is locked, and a comment isn't transcript — it's a
# remark about a stretch of audio, in its own list, in no export. The two
# constraints combine, which is the point of checking it in this harness.
puts "==> Commenting on a stretch of audio..."
COMMENT = "noise on this stretch".freeze
MORE = " — clipping too".freeze
# There's no key for this: the panel has a switch in the toolbar, and its own
# button makes a comment from whatever is selected.
check.call("the comments panel is hidden until its button is pressed",
           driver.find_elements(css: "#comments").none?(&:displayed?))
comments_toggle = driver.find_elements(xpath: "//button[@title='Show comments']").find(&:displayed?)
check.call("the toolbar offers a comments button", !comments_toggle.nil?)
comments_toggle&.click
panel = wait.until { driver.find_element(css: "#comments") }
check.call("pressing it shows the panel", panel.displayed?)

driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", 8.0, 1.0)
sleep 0.2
driver.find_element(xpath: "//section[@id='comments']//button[normalize-space()='Comment on selection']").click
comment_input =
  begin
    wait.until { driver.find_element(css: "#comments input[type=text]") }
  rescue Selenium::WebDriver::Error::TimeoutError
    nil
  end
check.call("'Comment on selection' made a comment row", !comment_input.nil?)
check.call("…without adding a segment (still #{segment_count.call})", segment_count.call == EXPECTED.length)

if comment_input
  # No Enter and no blur: a comment writes itself a second after the typing
  # stops, the way a segment's text does.
  comment_input.send_keys(COMMENT)
  sleep 1.8
  written = -> { Annotation.where(kit_id: ctx[:kit].id).pluck(:value).compact }
  check.call("the comment saved itself a second after typing, with no blur and no Enter",
             written.call.any? { |v| v.to_s.include?(COMMENT) })

  # And again when it's edited, rather than only on the first write.
  comment_input.send_keys(MORE)
  sleep 1.8
  check.call("editing it saved itself too",
             written.call.any? { |v| v.to_s.include?(COMMENT + MORE) })

  spans = ctx[:kit].reload.graph_projection
  comment_arc = spans[:arcs].find { |a| a[:name] == "CommentListItem" }
  check.call("it is a CommentListItem span of its own", !comment_arc.nil?)
  if comment_arc
    labels = spans[:labels].select { |l| l[:arc_iid] == comment_arc[:iid] }
    check.call("with one label, named Comment", labels.map { |l| l[:name] } == [ "Comment" ])
    check.call("carrying what was typed", labels.first[:value].to_s == COMMENT + MORE)
    beg_time = spans[:nodes].find { |n| n[:iid] == comment_arc[:beg_iid] }&.dig(:time)
    check.call("anchored at the selection (#{beg_time.inspect})", beg_time.to_f.round(1) == 8.0)
  end

  # The readable projection is the transcript, and a comment is not in it.
  ctx[:kit].snapshot
  projected = Segment.where(tree_id: ctx[:kit].reload.tree_id).pluck(:text).compact
  check.call("the transcript projection holds the segments but not the comment (#{projected.size} rows)",
             projected.any? && projected.none? { |t| t.to_s.include?(COMMENT) })

  rendered = driver.execute_script(
    "return Array.from(document.querySelectorAll('#segments .segment')).map(e => e.textContent).join(' ');"
  )
  check.call("nor does the segment list", !rendered.to_s.include?(COMMENT))

  # The time range plays the stretch the comment covers: it selects it on the
  # waveform, which is what play_current_span plays.
  driver.find_element(css: "#comments button[title='play this span']").click
  sleep 0.3
  # The header strip shows the selection's start and end; that's the readable
  # signal that the click moved it.
  shown_selection = driver.execute_script(<<~JS)
    const el = Array.from(document.querySelectorAll('span'))
      .find(e => /^\\s*\\d+(\\.\\d+)?\\s+\\d+(\\.\\d+)?\\s*$/.test(e.textContent || ''));
    return el ? el.textContent.trim() : null;
  JS
  check.call("clicking a comment's time range selects its span (header shows #{shown_selection.inspect})",
             shown_selection.to_s.split(/\s+/).map(&:to_f) == [ 8.0, 9.0 ])

  # The switch hides it again, and the comment is still there when it comes
  # back — the panel is a view of the graph, not where the comment lives.
  driver.find_elements(xpath: "//button[@title='Hide comments']").find(&:displayed?)&.click
  sleep 0.3
  check.call("the button hides the panel again", driver.find_elements(css: "#comments").none?(&:displayed?))
  driver.find_elements(xpath: "//button[@title='Show comments']").find(&:displayed?)&.click
  shown_again = wait.until { driver.find_element(css: "#comments input[type=text]") }
  check.call("and the comment is still there when it comes back",
             shown_again.attribute("value").to_s.include?(COMMENT))
end

# ── the log is the record: check what the tool actually wrote ─────────────
puts "==> Reading the annotation log..."
tree = ctx[:kit].reload.tree
annotations = Annotation.where(tree_id: tree.id).order(:id).to_a
names = {}
annotations.select { |a| a.message == "add" }.each do |a|
  a.value.to_s.split(",").each do |pair|
    iid, name = pair.split(":")
    names[iid.to_i] = name
  end
end
changed = annotations.select { |a| a.message == "change" && a.iid }
changed_names = changed.map { |a| names[a.iid] }.compact.uniq.sort
# The seeding writes the segments themselves — groups, and the Arc times that
# place them. Everything after the lock may only be Text.
check.call("no segment was deleted", annotations.none? { |a| a.message == "delete" })
check.call("nothing set a speaker or a section (changed: #{changed_names.join(', ')})",
           (changed_names & %w[ Speaker Name Section ]).empty?)
value_changes = changed.select { |a| names[a.iid] == "Text" }.map(&:value).compact
check.call("the only text written is what was typed", value_changes.all? { |v| v.to_s.include?(TYPED) || v.to_s.empty? })

# ── coming back to it ────────────────────────────────────────────────────
puts "==> Reloading — the segments should be the same ones, not new ones..."
driver.navigate.refresh
wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
sleep 1.5
after_reload = rows_now.call
check.call("still #{EXPECTED.length} segments after a reload (got #{after_reload.length})",
           after_reload.length == EXPECTED.length)
check.call("the typed text survived the reload",
           after_reload.any? { |r| r["text"].to_s.include?(TYPED) })
reloaded_captions = driver.execute_script(
  "return Array.from(document.querySelectorAll('#segments .reference-text')).map(e => e.textContent.trim());"
)
check.call("the captions came back too", EXPECTED.all? { |e| reloaded_captions.any? { |c| c.include?(e[:text]) } })
check.call("and it locked itself again", driver.execute_script("return !!(window.ldc && window.ldc.text_only)"))

# ── a kit that once held segments and no longer does ──────────────────────
# Deleting a segment leaves behind the anchors its times pointed at, so such a
# kit still has nodes in it while having no segments. Counting nodes to decide
# whether to create them left those kits with an empty waveform for good — the
# annotator has nothing to type into and nothing says why.
#
# Deleting isn't something this mode allows, so the delete goes into the log
# directly, which is the state those kits were found in.
puts "==> A kit whose segments were deleted, leaving the anchors..."
segment_iids = ctx[:kit].reload.graph_projection[:arcs]
  .select { |a| a[:name] == "SegmentListItem" }.map { |a| a[:iid] }
segment_iids.each do |iid|
  Annotation.create!(
    tree_id: tree.id, task_id: ctx[:task].id, user_id: ctx[:user].id,
    kit_id: ctx[:kit].id, message: "delete", iid: iid, last_iid: "0"
  )
end
after_delete = ctx[:kit].reload.graph_projection
check.call("the deletes left #{after_delete[:nodes].size} anchors and no segments",
           after_delete[:arcs].none? { |a| a[:name] == "SegmentListItem" } && after_delete[:nodes].any?)

driver.navigate.refresh
wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
reseeded =
  begin
    wait.until { segment_count.call == EXPECTED.length }
    true
  rescue Selenium::WebDriver::Error::TimeoutError
    false
  end
check.call("the imported spans were created again (#{EXPECTED.length}; got #{segment_count.call})", reseeded)
check.call("the orphaned anchors didn't stop it",
           driver.execute_script("return window.ldc.nodes.size") > 0)

# ── closing the kit ───────────────────────────────────────────────────────
# The transcript's shape is locked; finishing the work isn't part of that. This
# was refused when the lock read the messages rather than the operations —
# 'done' is a message, so the annotator couldn't hand the kit back.
puts "==> Closing the kit..."
close_kit_btn = wait.until { driver.find_element(css: 'button:has(svg path[d^="M10 18a8 8 0 100-16"])') }
close_kit_btn.click
done_btn = wait.until { driver.find_element(xpath: "//dialog//button[contains(., 'Done')]") }
done_btn.click

closed =
  begin
    deadline = Time.now + 15
    sleep 0.3 until ctx[:kit].reload.state == "done" || Time.now > deadline
    ctx[:kit].reload.state == "done"
  rescue StandardError
    false
  end
check.call("a locked kit can still be closed (state=#{ctx[:kit].reload.state.inspect})", closed)
check.call("…and the 'done' message reached the log",
           Annotation.where(kit_id: ctx[:kit].id, message: "done").any?)

driver.quit rescue nil

puts ""
puts "==> transcribe_text_only"
passes.each  { |l| puts "  \e[32mPASS\e[0m #{l}" }
failures.each { |l| puts "  \e[31mFAIL\e[0m #{l}" }
puts ""
if failures.empty?
  puts "PASS (#{passes.length} checks)"
  exit 0
else
  puts "FAIL (#{failures.length} of #{passes.length + failures.length} checks failed)"
  exit 1
end
