#!/usr/bin/env ruby
# Automated counterpart of script/transcription_repl.rb. Same setup, browser
# launch, sign-in, and dump+assert phases — but instead of waiting for a human
# to make annotations and close the window, it drives Selenium through a
# scripted gesture sequence (set selection on the waveform, press Enter to
# create a segment, type text into the auto-focused textarea, blur to flush).
#
# It then reloads the page and re-reads the segment rows, which is the check
# that catches "the annotation looked saved but wasn't": the tool rebuilds
# itself from /kits/get, so the text, times, speaker and section have to come
# back out of the server rather than out of the client's own state.
#
#   1. Start the repl server in another terminal:
#         bin/repl
#
#   2. Run this script:
#         bundle exec ruby script/transcription_auto.rb
#
# Set DUMP_ALL=1 to also print SELECT * over every table in the DB before the
# assertions run — handy for diagnosing why an assertion failed.
#
# Same exit codes as the manual script: 0 = PASS, 1 = FAIL.

ENV["RAILS_ENV"] ||= "repl"

require_relative "transcription_repl_lib"

TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

puts "==> Setting up data..."
ctx = TranscriptionReplLib.setup_data

puts ""
puts "==> Launching Chrome..."
driver = TranscriptionReplLib.launch_browser_signed_in(
  user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task]
)
at_exit { driver.quit rescue nil }

# ── automation ───────────────────────────────────────────────────────────
# Two segments on the 10-second tone. The structural checks only require
# *one* segment with Arc+time and Text+content, but doing two exercises the
# segment-list growth path and proves the second-line shortcut also works.
# Segment 1 also gets a Speaker assignment; segment 2 opens a Section — so
# the resulting DB has all four annotation kinds (Arc/Text/Speaker/Section).
SEGMENTS = [
  { beg: 0.5, len: 1.5, text: "automated first segment",  speaker: "Alice" },
  { beg: 3.0, len: 1.5, text: "automated second segment", section: "intro" },
].freeze

# Drives the "open help_screen → press 'n' for new → input_screen → type → Enter"
# pattern that both Speaker (Ctrl+S) and Section (Ctrl+[) use.
#
# We dispatch the modifier keystroke as a synthetic KeyboardEvent rather than
# via Selenium's send_keys [:control, …] because real Ctrl+S triggers Chrome's
# "Save Page" shortcut at the OS level — which would block the test. The Svelte
# t_keydown handler still fires off the synthetic event and routes through the
# inputmap.control map normally.
def name_via_modal(driver, wait, modifier_key, value)
  code = { "s" => "KeyS", "[" => "BracketLeft", "]" => "BracketRight" }.fetch(modifier_key)

  driver.execute_script(<<~JS, modifier_key, code)
    const ta = document.querySelector('#segments .segment.active-segment textarea.ann-segment');
    if (!ta) throw new Error('no active textarea — cannot open name modal');
    ta.focus();
    ta.dispatchEvent(new KeyboardEvent('keydown', {
      key: arguments[0], code: arguments[1],
      ctrlKey: true, bubbles: true, cancelable: true,
    }));
  JS
  sleep 0.25  # help_screen_open uses a 100ms setTimeout to focus its tabindex=0 div

  # Press 'n' (the "new …" option set up by set_speaker_helper_new_helper) on
  # the now-focused help_screen div.
  driver.execute_script(<<~JS)
    document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {
      key: 'n', code: 'KeyN', bubbles: true, cancelable: true,
    }));
  JS
  sleep 0.25  # input_screen mounts; same 100ms focus timeout

  # The input has a stable id ("set_new_speaker_input" — used by both the speaker
  # and section flows). Real key events here are fine because nothing intercepts
  # plain typing or Enter at the OS level.
  input = wait.until { driver.find_element(id: "set_new_speaker_input") }
  input.send_keys(value)
  input.send_keys(:enter)
  sleep 0.4  # let change_value POST round-trip
end

wait = Selenium::WebDriver::Wait.new(timeout: 30)

# 1. Wait for the Svelte side to come up. `ldc` is the global from work.js;
#    `ldc.wc` is set on a 1s interval in maintranscription.svelte once the
#    Waveform component mounts.
puts ""
puts "==> Waiting for transcription tool to mount..."
wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }

# By now Workflow#assign_kit has run server-side (the work URL drives it) and
# Kit#create_tree has populated kit.tree_id. Resolve the tree into the ctx so
# the rest of the script can use ctx[:tree] without checking nil.
ctx[:kit].reload
ctx[:tree] = ctx[:kit].tree
raise "kit.tree_id still nil after work-page mount — workflow assign_kit didn't run" unless ctx[:tree]
puts "  -> tree resolved post-assign: ##{ctx[:tree].id} uid=#{ctx[:tree].uid.inspect}"

# 2. Wait for the audio buffer to load. The waveform canvas only gets the
#    `active` class after the channel has rendered samples.
puts "==> Waiting for waveform canvas to render..."
wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
sleep 0.5  # let any post-load $effect drain

# 2b. Belt-and-suspenders: the training guide (transcription_guide.svelte) is
#     suppressed in repl mode server-side (config.x.transcription_repl), so it
#     shouldn't be here. If it ever is, close it before we touch the keyboard —
#     its window capture-phase keydown handler swallows Enter to drive its own
#     steps, which would eat the segment-add Enters below. Immediate check only
#     (no wait): if the guide were going to open, it already has by now.
guide_close = driver.find_elements(css: "[aria-label='Close guide']").find(&:displayed?)
if guide_close
  guide_close.click
  wait.until { driver.find_elements(css: "[aria-label='Close guide']").none?(&:displayed?) }
  puts "==> Transcription guide was open; dismissed it."
end

# Install a fetch hook that records every POST to /annotations along with the
# parsed inner JSON (the { messages, kit_uid, client_time }
# envelope built by submit_form_old in modification2.js). We dump the captured
# requests to the console after the segment edits, so the first message-group
# the JS sends to the AnnotationsController is visible.
driver.execute_script(<<~JS)
  if (!window.__origFetch) {
    window.__origFetch = window.fetch.bind(window);
    window.__annotationsRequests = [];
    window.fetch = function(url, init) {
      try {
        const isAnn = typeof url === 'string' && url.indexOf('/annotations') === 0
                      && init && (init.method || '').toUpperCase() === 'POST';
        if (isAnn) {
          let outer = init.body;
          try { outer = JSON.parse(init.body); } catch (e) { /* leave as string */ }
          let inner = outer && outer.json;
          if (typeof inner === 'string') {
            try { inner = JSON.parse(inner); } catch (e) { /* leave */ }
          }
          window.__annotationsRequests.push({
            url: url,
            task_user_id: outer && outer.task_user_id,
            kit_uid: inner && inner.kit_uid,
            client_time: inner && inner.client_time,
            messages: inner && inner.messages,
          });
        }
      } catch (e) { /* never break the real fetch */ }
      return window.__origFetch(url, init);
    };
  }
JS

# 3. The keyboard div is what receives the Enter that triggers
#    play_current_span_and_add_transcript_line_and_activate via the keymap.
keyboard = driver.find_element(css: ".keyboard")

SEGMENTS.each_with_index do |seg, i|
  puts "==> Segment #{i + 1}: selection #{seg[:beg]}s + #{seg[:len]}s, text=#{seg[:text].inspect}"

  prior_count = driver.find_elements(css: "#segments .segment").length

  driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", seg[:beg], seg[:len])
  sleep 0.2

  keyboard.click
  keyboard.send_keys(:enter)

  # The previous segment's textarea stays mounted until the server roundtrips
  # the segment-add and `set_active_transcript_line_to_last_created` swaps the
  # active id over. If we type before that, our keystrokes land in the OLD
  # textarea and the new segment's Text node ends up empty. So wait for two
  # things: the new segment row to appear, AND for it to become the active one
  # (the textarea is only rendered inside `.active-segment`).
  wait.until { driver.find_elements(css: "#segments .segment").length == prior_count + 1 }
  wait.until do
    segs = driver.find_elements(css: "#segments .segment")
    segs.last && segs.last.attribute("class").to_s.include?("active-segment")
  end
  textarea = wait.until { driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment") }
  textarea.send_keys(seg[:text])

  if seg[:speaker]
    puts "          speaker=#{seg[:speaker].inspect} (Ctrl+S → 'n' → type → Enter)"
    # Opening the help_screen moves focus off the textarea, which fires onblur
    # → t_blur → t_patch — so the typed text is flushed as a side effect of
    # opening the speaker modal. No separate Tab needed.
    name_via_modal(driver, wait, "s", seg[:speaker])
  elsif seg[:section]
    puts "          section=#{seg[:section].inspect} (Ctrl+[ → 'n' → type → Enter)"
    name_via_modal(driver, wait, "[", seg[:section])
  else
    # Plain segment with no speaker/section — Tab to flush the debounced patch.
    textarea.send_keys(:tab)
    sleep 0.4
  end
end

puts ""
puts "==> Letting any pending saves settle..."
sleep 1.5

# Dump every POST /annotations the JS made during the segment edits, in
# chronological order. The very first one is the segment-1 add (an 'add'
# message group from add_audio_to_list) — useful for sanity-checking the
# message shape independent of what the controller does with it.
ann_requests = driver.execute_script("return window.__annotationsRequests || [];")
puts ""
puts "==> Captured POST /annotations (#{ann_requests.size} request#{ann_requests.size == 1 ? "" : "s"}):"
ann_requests.each_with_index do |r, i|
  puts ""
  puts "── request[#{i}]  task_user_id=#{r["task_user_id"].inspect}  kit_uid=#{r["kit_uid"].inspect}  client_time=#{r["client_time"].inspect}"
  msgs = r["messages"] || []
  puts "   #{msgs.size} message#{msgs.size == 1 ? "" : "s"}:"
  msgs.each_with_index do |m, j|
    puts "     [#{j}] node=#{m["node"].inspect}  message=#{m["message"].inspect}  value=#{m["value"].inspect}"
  end
end

# ── annotation-tool download (BEFORE marking done) ──────────────────────
# Drive the download trigger inside the transcription tool itself (the
# ArrowDownToLine icon button rendered when the kit_type has the
# `export_transcript` constraint, controls.svelte:197). This proves the
# in-tool path also produces a usable transcript, and gives us a TSV to
# compare against the dashboard zip later. Install the URL.createObjectURL
# hook NOW so this download's blob is also captured.
puts ""
puts "==> Triggering download from the annotation tool..."
driver.execute_script(<<~JS)
  if (!window.__origCreateObjectURL) {
    window.__origCreateObjectURL = URL.createObjectURL.bind(URL);
    URL.createObjectURL = function(blob) {
      window.__capturedBlob = blob;
      return window.__origCreateObjectURL(blob);
    };
  }
JS

ann_dl_trigger = wait.until { driver.find_element(css: "button:has(svg.lucide-arrow-down-to-line)") }
ann_dl_trigger.click

# DownloadTranscriptDialog renders inside a <dialog> opened via showModal.
# The dashboard's "Download Transcript" Dialog uses bits-ui (role=dialog) and
# has a Description "Download one or more transcripts" — the annotation tool's
# only has the title. Match the open <dialog> with the title text, scoped so
# we don't grab the bits-ui one (which isn't even on this page yet).
ann_dialog = wait.until do
  driver.find_elements(css: "dialog[open]").find do |d|
    d.displayed? && d.text.include?("Download Transcript")
  end
end
puts "  -> annotation-tool dialog opened"

# Fill the filename input — without it, <a download={download_transcript_filename}>
# renders with no `download` attribute (Svelte omits attributes whose value is
# undefined), so the link can be hard to detect AND won't trigger a real
# download if you click it. With a value, the attribute is present.
ann_filename_input = ann_dialog.find_element(xpath: ".//input[@type='text']")
ann_filename_input.send_keys("annotation_tool_transcript")

# Check Include Headers / Speaker / Section.
ann_dialog.find_elements(xpath: ".//input[@type='checkbox']").first(3).each_with_index do |cb, i|
  driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", cb)
  cb.click unless cb.selected?
  puts "  -> annotation-tool checkbox[#{i}] checked"
end

# Reset the capture slot so we know the blob we read after Create Preview is
# this download's blob, not something stale.
driver.execute_script("window.__capturedBlob = null;")

# Click "Create Preview" (note: button label differs from the dashboard's "Create").
ann_create = ann_dialog.find_element(xpath: ".//button[normalize-space()='Create Preview']")
ann_create.click

# Wait for window.__capturedBlob to be populated by the URL.createObjectURL
# hook — that's the most reliable signal that create_download_url ran. Don't
# wait for the <a download> link in the DOM: it's only rendered after
# `download_transcript_url` is set, which is after this same hook fires.
wait.until { driver.execute_script("return !!window.__capturedBlob;") }

# Read the captured Blob (latest from window.__capturedBlob).
ann_tool_tsv = nil
ann_tsv_b64 = driver.execute_async_script(<<~JS)
  const cb = arguments[arguments.length - 1];
  try {
    const blob = window.__capturedBlob;
    if (!blob) return cb('ERR:no captured blob');
    const reader = new FileReader();
    reader.onload = () => {
      const r = reader.result || '';
      const c = r.indexOf(',');
      cb(c >= 0 ? r.slice(c + 1) : 'ERR:no comma');
    };
    reader.onerror = () => cb('ERR:FileReader ' + String(reader.error));
    reader.readAsDataURL(blob);
  } catch (e) { cb('ERR:' + String(e)); }
JS
if ann_tsv_b64.is_a?(String) && !ann_tsv_b64.start_with?("ERR:")
  require "base64"
  ann_tool_tsv = Base64.decode64(ann_tsv_b64)
  puts ""
  puts "==> Annotation-tool transcript (#{ann_tool_tsv.bytesize} bytes):"
  puts ann_tool_tsv.lines.map { |l| "  #{l}" }.join
else
  warn "  [WARN] failed to capture annotation-tool blob: #{ann_tsv_b64.inspect}"
end

# Close the dialog so the close-kit (✓) button below it is reachable.
# Escape via driver.action targets whatever's focused — which may not be the
# <dialog>. Calling .close() on every open <dialog> is deterministic.
driver.execute_script("document.querySelectorAll('dialog[open]').forEach(d => d.close());")
sleep 0.4

# ── reload and re-read (does the work survive a round trip?) ─────────────
# Everything above proves the client *thinks* it saved: the DOM updated and
# POST /annotations came back clean. It doesn't prove the server can serve the
# work back. Real bugs have looked exactly like that — the segments look right
# until you refresh, and the text or the timestamps are gone. So reload, let the
# tool rebuild itself from /kits/get, and read the rows out of the DOM again.
puts ""
puts "==> Reloading the page and re-reading the segments..."
reload_passes = []
reload_failures = []
expect_reload = ->(label, ok) { ok ? reload_passes << label : reload_failures << label }

driver.navigate.refresh
wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
begin
  wait.until { driver.find_elements(css: "#segments .segment").length >= SEGMENTS.length }
rescue Selenium::WebDriver::Error::TimeoutError
  # Not fatal here — the count assertion below reports it with the real number.
end

# One hash per rendered row. The active row renders a textarea instead of the
# .transcript div, so read whichever is there.
reloaded_rows = driver.execute_script(<<~JS)
  return Array.from(document.querySelectorAll('#segments .segment')).map(function (el) {
    const textarea = el.querySelector('textarea.ann-segment');
    const transcript = el.querySelector('.transcript');
    const beg = el.querySelector('.btime');
    const end = el.querySelector('.etime');
    const speaker = el.querySelector('.speaker span');
    const section = el.querySelector('.section');
    return {
      iid: el.dataset.iid,
      beg: beg ? beg.textContent.trim() : null,
      end: end ? end.textContent.trim() : null,
      text: textarea ? textarea.value : (transcript ? transcript.textContent.trim() : null),
      speaker: speaker ? speaker.textContent.trim() : null,
      section: section ? section.textContent.trim() : null,
    };
  });
JS

puts "  -> #{reloaded_rows.size} segment row#{reloaded_rows.size == 1 ? "" : "s"} after reload:"
reloaded_rows.each_with_index do |r, i|
  puts "     [#{i}] iid=#{r["iid"]}  #{r["beg"]}–#{r["end"]}  text=#{r["text"].inspect}  speaker=#{r["speaker"].inspect}  section=#{r["section"].inspect}"
end

expect_reload.call("segment rows survive a reload (#{reloaded_rows.size} of #{SEGMENTS.length})",
  reloaded_rows.size == SEGMENTS.length)

# Rows render in time order, so they line up with SEGMENTS.
SEGMENTS.each_with_index do |seg, i|
  row = reloaded_rows[i]
  unless row
    expect_reload.call("segment #{i + 1} is present after reload", false)
    next
  end

  expect_reload.call("segment #{i + 1} text survived: #{seg[:text].inspect}",
    row["text"].to_s.strip == seg[:text])

  # Compare the times numerically — the DOM pads them to three decimals, and
  # a formatting change shouldn't fail this.
  beg = Float(row["beg"], exception: false)
  fin = Float(row["end"], exception: false)
  expect_reload.call("  …begin time survived (#{seg[:beg]})",
    beg && (beg - seg[:beg]).abs < 0.05)
  expect_reload.call("  …end time survived (#{seg[:beg] + seg[:len]})",
    fin && (fin - (seg[:beg] + seg[:len])).abs < 0.05)

  if seg[:speaker]
    expect_reload.call("  …speaker survived (#{seg[:speaker]})", row["speaker"] == seg[:speaker])
  end
  if seg[:section]
    expect_reload.call("  …section survived (#{seg[:section]})", row["section"] == seg[:section])
  end
end

# The rows the browser drew should be the rows the server would serve: same
# count, same text, same times. If these disagree, the payload is right and the
# client dropped something (or the reverse).
served = ctx[:kit] && ctx[:kit].tree_id ? NodeDerivation.for_tree(ctx[:kit].reload.tree_id) : nil
if served
  served_texts = served.nodes.each_value.select { |n| n[:name] == "Text" }
                       .map { |n| served.value_for(n)[:value].to_s }
                       .reject(&:empty?)
  expect_reload.call("the payload holds the same texts the page shows",
    served_texts.sort == reloaded_rows.map { |r| r["text"].to_s.strip }.reject(&:empty?).sort)
end

# The client unfolds the payload into the annotation graph — time anchors, the
# spans between them, the labels on those spans — without the server sending
# anything extra. Rebuild the transcript from those rows here and check it
# against the rows the page drew: if they agree, the graph is a sufficient
# description of the transcript on its own, which is what it has to be before
# anything is allowed to render from it.
graph_rows = driver.execute_script(<<~JS)
  // ldc.graph is the client's own state: folded out of the payload at load and
  // then maintained message by message. The transcript is rendered from it.
  const g = window.ldc && window.ldc.graph;
  if(!g || !g.nodes.length) return null;
  const time = new Map(g.nodes.map( (n) => [ n.iid, n.time ] ));
  const labels = new Map();
  for(const l of g.labels){
    if(!labels.has(l.arc_iid)) labels.set(l.arc_iid, {});
    labels.get(l.arc_iid)[l.name] = l.value;
  }
  return {
    source: g.source,
    rendered: Array.from((window.ldc.segmap || new Map()).values())
                   .map( (r) => ({ beg: r.beg, end: r.end, text: r.text, speaker: r.speaker }) ),
    // The wire format is unchanged: no graph rows were sent, only the flat
    // nodes and values the tool has always received.
    payload_keys: Object.keys(window.ldc.obj2 || {}).sort(),
    counts: { nodes: g.nodes.length, arcs: g.arcs.length, labels: g.labels.length },
    segments: g.arcs.filter( (a) => a.name === 'SegmentListItem' ).map( (a) => ({
      beg: time.get(a.beg_iid), end: time.get(a.end_iid),
      text: (labels.get(a.iid) || {}).Text || '',
      speaker: (labels.get(a.iid) || {}).Speaker || '',
    }) ).sort( (x, y) => x.beg - y.beg ),
    sections: g.arcs.filter( (a) => a.name === 'SectionListItem' ).map( (a) => (labels.get(a.iid) || {}).Name ),
  };
JS

if graph_rows.nil?
  expect_reload.call("the client unfolded an annotation graph from the payload", false)
else
  counts = graph_rows["counts"]
  expect_reload.call("the client folded its own annotation graph " \
                     "(#{counts["nodes"]} anchors, #{counts["arcs"]} arcs, #{counts["labels"]} labels)",
    counts["arcs"] >= SEGMENTS.length && counts["nodes"] >= SEGMENTS.length * 2 &&
    graph_rows["source"] == "live")
  expect_reload.call("  …out of the payload as it always was, with nothing added to the wire",
    !graph_rows["payload_keys"].include?("graph") &&
    (%w[ nodes node_values last_iid ] - graph_rows["payload_keys"]).empty?)

  derived = graph_rows["segments"]
  expect_reload.call("the graph describes one span per segment (#{derived.size} of #{SEGMENTS.length})",
    derived.size == SEGMENTS.length)

  SEGMENTS.each_with_index do |seg, i|
    row = derived[i]
    next expect_reload.call("graph segment #{i + 1} is present", false) unless row

    expect_reload.call("  …graph text matches the page (#{seg[:text].inspect})",
      row["text"].to_s.strip == seg[:text])
    expect_reload.call("  …graph times match the page (#{seg[:beg]}–#{seg[:beg] + seg[:len]})",
      row["beg"] && row["end"] &&
      (row["beg"].to_f - seg[:beg]).abs < 0.05 &&
      (row["end"].to_f - (seg[:beg] + seg[:len])).abs < 0.05)
    if seg[:speaker]
      expect_reload.call("  …graph speaker matches the page (#{seg[:speaker]})", row["speaker"] == seg[:speaker])
    end
  end

  sections = SEGMENTS.filter_map { |s| s[:section] }
  expect_reload.call("sections are their own spans, labelled by Name (#{sections.join(", ")})",
    graph_rows["sections"].compact.sort == sections.sort)
end

# ── reshaping what's there: split, merge, delete ─────────────────────────
# Everything above only ever adds. These three change the shape of a tree that
# already exists, and they touch the most machinery: splitting re-times the
# segment it splits and allocates two anchors and a segment, merging re-times
# one and deletes another, and deleting takes a group out from under rows that
# point at it.
#
# Driving them takes three things, none of them obvious:
#
#   ldc.crnt   split and merge read it, and only set_active_transcript_line_helper
#              sets it — creating a segment doesn't. Click the row.
#   the cursor split_segment_at_cursor takes channels' cursortime, which derives
#              from mouse position; a synthetic mousedown with clientX sets it.
#   the keys   ',' 'm' 'd' are in input_map.control (bindings.js:132-134), so
#              they're modifier + key on the focused textarea — the same route
#              the speaker/section modals use — not plain keys on .keyboard,
#              where those letters mean cursor movement instead.
#
# Done on a third segment which is then deleted, so the kit ends up exactly as
# the checks above left it.
puts ""
puts "==> Reshaping: split, merge, delete (on a scratch third segment)"
shape_passes = []
shape_failures = []
expect_shape = ->(label, ok) { ok ? shape_passes << label : shape_failures << label }

segment_count = -> { driver.find_elements(css: "#segments .segment").length }
graph_counts = -> {
  driver.execute_script(<<~JS)
    const g = window.ldc.graph;
    return { anchors: g.nodes.length, arcs: g.arcs.length,
             segments: g.arcs.filter( (a) => a.name === 'SegmentListItem' ).length,
             rows: { nodes: g.nodes, arcs: g.arcs, labels: g.labels } };
  JS
}
# Modifier + key on the active segment's textarea: input_map.control.
modifier_key = ->(key, code) do
  driver.execute_script(<<~JS, key, code)
    const ta = document.querySelector('#segments .segment.active-segment textarea.ann-segment');
    if(!ta) throw new Error('no active textarea');
    ta.focus();
    ta.dispatchEvent(new KeyboardEvent('keydown', {
      key: arguments[0], code: arguments[1], ctrlKey: true, bubbles: true, cancelable: true,
    }));
  JS
  sleep 1.2
end
# Put the cursor at a time by clicking the waveform. The canvas shows whatever
# window is scrolled to, so sample two positions to learn the mapping rather
# than assuming the whole file is visible.
click_waveform_at = ->(fraction) do
  driver.execute_script(<<~JS, fraction)
    const c = document.querySelector('canvas.waveform-waveform.active');
    const r = c.getBoundingClientRect();
    c.dispatchEvent(new MouseEvent('mousedown', {
      clientX: r.left + r.width * arguments[0], clientY: r.top + r.height / 2,
      bubbles: true, cancelable: true,
    }));
  JS
  sleep 0.4
  driver.execute_script("const e = document.querySelector('span.absolute.text-red-500'); return e ? parseFloat(e.textContent) : null")
end
cursor_to = ->(target) do
  a = click_waveform_at.call(0.25)
  b = click_waveform_at.call(0.75)
  span = (b - a) / 0.5
  offset = a - 0.25 * span
  click_waveform_at.call((target - offset) / span)
end


# The client's graph, against the server's own projection of the annotation log.
# This is what replaced the fold-and-compare audit: the log is the record, so
# the check that matters is whether what the client holds is what the log says.
# Polls, since the messages for the edit just made may still be in flight.
normalise_graph = ->(g) do
  key = ->(h, *names) { names.map { |n| h[n.to_s] || h[n] } }
  {
    nodes: (g["nodes"] || g[:nodes] || []).map { |n| key.call(n, :iid, :n_iid, :docid).map(&:to_s) + [ (key.call(n, :time).first&.to_f) ] }.sort_by(&:first),
    arcs: (g["arcs"] || g[:arcs] || []).map { |a| key.call(a, :iid, :name, :arc_node_iid, :beg_iid, :end_iid).map(&:to_s) }.sort_by(&:first),
    labels: (g["labels"] || g[:labels] || []).map { |l| key.call(l, :iid, :arc_iid, :name, :value).map(&:to_s) }.sort_by(&:first),
  }
end
graph_matches_server = -> do
  client = driver.execute_script("const g = window.ldc.graph; return { nodes: g.nodes, arcs: g.arcs, labels: g.labels }")
  10.times do
    return true if normalise_graph.call(client) == normalise_graph.call(ctx[:kit].reload.graph_projection)
    sleep 0.3
    client = driver.execute_script("const g = window.ldc.graph; return { nodes: g.nodes, arcs: g.arcs, labels: g.labels }")
  end
  false
end

# ── a selection that runs past the end of the audio ───────────────────────
# A segment's times can run a little past the file — imported times rarely
# match to the millisecond, and it lands on the last segment. Selecting one
# used to be refused outright, which left the previous selection in place, so
# playing the last segment played whichever was played before it.
puts ""
puts "==> A selection past the end of the audio..."
clamp_passes = []
clamp_failures = []
expect_clamp = ->(label, ok) { ok ? clamp_passes << label : clamp_failures << label }

read_selection = lambda do
  driver.execute_script(<<~'JS')
    const el = Array.from(document.querySelectorAll('span'))
      .find(e => /^\s*\d+(\.\d+)?\s+\d+(\.\d+)?\s*$/.test(e.textContent || ''));
    return el ? el.textContent.trim().split(/\s+/).map(Number) : null;
  JS
end

driver.execute_script("window.ldc.wc.set_current_selection(1.0, 1.0)")
sleep 0.2
before_clamp = read_selection.call
# The test tone is 10s; 8.0 + 5.0 runs 3 seconds past it.
driver.execute_script("window.ldc.wc.set_current_selection(8.0, 5.0)")
sleep 0.2
after_clamp = read_selection.call
expect_clamp.call("a selection running past the end is clamped to it (#{after_clamp.inspect})",
  after_clamp == [ 8, 10 ])
expect_clamp.call("…rather than leaving the one before it (#{before_clamp.inspect})",
  after_clamp != before_clamp)

# A selection that starts past the end has nothing to play, and says so.
driver.execute_script("window.ldc.wc.set_current_selection(12.0, 1.0)")
sleep 0.2
expect_clamp.call("a selection starting past the end is refused, and the last good one stands",
  read_selection.call == [ 8, 10 ])

# ── Tab from the waveform reaches the text window ─────────────────────────
# Clicking a segment then pressing Tab has always worked: Tab re-activates the
# row that was already active. Clicking the *waveform* first left nothing
# active, so Tab restored nothing and looked dead. It picks the segment at the
# cursor now.
puts ""
puts "==> Tab from the waveform, with no segment clicked..."
tab_passes = []
tab_failures = []
expect_tab = ->(label, ok) { ok ? tab_passes << label : tab_failures << label }
keyboard = driver.find_element(css: ".keyboard") # the reload replaced the old handle
# Put the cursor inside the first segment (0.5–2.0) by clicking the waveform
# there — which is the gesture being described, and what leaves the keyboard
# focused with no segment active.
placed = cursor_to.call(1.0)
sleep 0.3
# The page was reloaded just above and no segment has been clicked since, which
# is the state that made Tab look dead.
expect_tab.call("clicking the waveform leaves no segment active (cursor at #{placed.round(2)}s)",
  driver.execute_script("return !document.querySelector('#segments .segment.active-segment')"))
keyboard.send_keys(:tab)
sleep 0.6
focused_iid = driver.execute_script(<<~JS)
  const el = document.querySelector('#segments .segment.active-segment');
  return el ? el.getAttribute('data-iid') : null;
JS
expect_tab.call("tab activates the segment the cursor is in (iid #{focused_iid.inspect}, wanted 5)",
  focused_iid.to_s == "5")
expect_tab.call("…and its textarea has focus",
  driver.execute_script("return !!document.activeElement && document.activeElement.classList.contains('ann-segment')"))

# Everything a click does, not just the focus: the row's audio is selected on
# the waveform, and ldc.crnt is set — which is what split and merge act on.
# The header strip shows "<selection start> <selection end>". Single-quoted
# heredoc: Ruby would otherwise eat the regex's backslashes before JS sees it.
tab_selection = driver.execute_script(<<~'JS')
  const el = Array.from(document.querySelectorAll('span'))
    .find(e => /^\s*\d+(\.\d+)?\s+\d+(\.\d+)?\s*$/.test(e.textContent || ''));
  return el ? el.textContent.trim().split(/\s+/).map(Number) : null;
JS
expect_tab.call("…and the segment's audio is selected (#{tab_selection.inspect}, wanted 0.5–2.0)",
  tab_selection == [ 0.5, 2.0 ])
expect_tab.call("…and ldc.crnt points at it, so split and merge would work",
  driver.execute_script("return window.ldc.crnt").to_i == 5)

started_with = segment_count.call
driver.execute_script("window.ldc.wc.set_current_selection(6.0, 2.0)")
sleep 0.3
keyboard.click
keyboard.send_keys(:enter)
wait.until { segment_count.call == started_with + 1 }
sleep 0.5
expect_shape.call("a scratch segment to reshape (#{segment_count.call})",
  segment_count.call == started_with + 1)

# Activate it through the navigation path, which is what sets ldc.crnt.
driver.find_elements(css: "#segments .segment").last.click
sleep 0.8
expect_shape.call("the active segment is the one split and merge will act on",
  driver.execute_script("return window.ldc.crnt").to_i > 0)

cursor = cursor_to.call(7.0)
expect_shape.call("the cursor is inside it (#{cursor}s of 6.0–8.0)",
  cursor && cursor > 6.0 && cursor < 8.0)

modifier_key.call(",", "Comma")
after_split = segment_count.call
expect_shape.call("splitting made it two (#{started_with + 1} → #{after_split})",
  after_split == started_with + 2)
split_graph = graph_counts.call
expect_shape.call("  …the graph has a span for each (#{split_graph["segments"]})",
  split_graph["segments"] == after_split)
expect_shape.call("  …and an anchor pair per span (#{split_graph["anchors"]})",
  split_graph["anchors"] >= after_split * 2)
expect_shape.call("  …and says what the server projects from the log", graph_matches_server.call)

# Give the second half some text before merging: merging concatenates the two
# segments' text and sends that as a change to the first one's Text node, and
# that path is only reached when the second half has something in it.
driver.find_elements(css: "#segments .segment").last.click
sleep 0.5
driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment").send_keys("second half text")
sleep 0.5
# Merge acts on ldc.crnt and takes the *following* segment, so make the first
# half current again.
driver.find_elements(css: "#segments .segment")[-2].click
sleep 0.8

modifier_key.call("m", "KeyM")
after_merge = segment_count.call
merged_text = driver.execute_script("return Array.from(window.ldc.segmap.values()).map( (s) => s.text )")
expect_shape.call("  …and carried the merged-away text into the survivor",
  merged_text.any? { |t| t.to_s.include?("second half text") })
expect_shape.call("merging put them back together (#{after_split} → #{after_merge})",
  after_merge == after_split - 1)
merge_graph = graph_counts.call
expect_shape.call("  …the graph dropped the merged-away span (#{merge_graph["segments"]})",
  merge_graph["segments"] == after_merge)
expect_shape.call("  …and says what the server projects from the log", graph_matches_server.call)

# ctrl+d arms a confirm button on the active row; clicking it does the delete.
modifier_key.call("d", "KeyD")
delete_button = driver.find_elements(css: "#segments button").find { |b| b.text.strip == "delete" }
if delete_button
  delete_button.click
  sleep 1.2
end
after_delete = segment_count.call
expect_shape.call("deleting removed it (#{after_merge} → #{after_delete})",
  after_delete == started_with)
delete_graph = graph_counts.call
expect_shape.call("  …the graph dropped its span and labels (#{delete_graph["segments"]})",
  delete_graph["segments"] == after_delete)
expect_shape.call("  …and says what the server projects from the log", graph_matches_server.call)

# The server has to agree: reload and count what comes back out of /kits/get.
driver.navigate.refresh
wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
sleep 1.5
expect_shape.call("what survives a reload is the original #{started_with} (#{segment_count.call})",
  segment_count.call == started_with)
expect_shape.call("the log still replays without anomalies",
  NodeDerivation.for_tree(ctx[:kit].reload.tree_id).anomalies.empty?)
keyboard = driver.find_element(css: ".keyboard")

# ── mark the kit done ────────────────────────────────────────────────────
# The "close kit" trigger in the header is a green check-circle icon button
# (controls.svelte:274). It opens a <dialog> with a "✓ Done" button
# (CloseKitDialog.svelte:32) that calls done(null) → submits a 'done' message
# → advances kit.state to 'done' on the server.
puts "==> Clicking the close-kit (✓) trigger..."
close_kit_btn = wait.until { driver.find_element(css: 'button:has(svg path[d^="M10 18a8 8 0 100-16"])') }
close_kit_btn.click

puts "==> Confirming Done in the close-kit dialog..."
done_btn = wait.until { driver.find_element(xpath: "//dialog//button[contains(., 'Done')]") }
done_btn.click

# Wait for the kit to actually transition to 'done' on the server. Don't trust
# wall-clock sleep — poll the DB directly. The 'done' message goes through the
# same /annotations promise chain as the segment edits, so it lands behind any
# in-flight saves.
puts "==> Waiting for kit.state -> 'done' on the server..."
deadline = Time.now + 15
loop do
  break if ctx[:kit].reload.state == "done"
  raise "kit.state never became 'done' (last seen #{ctx[:kit].state.inspect})" if Time.now > deadline
  sleep 0.25
end

# ── download the transcript via the dashboard ────────────────────────────
# Drive the same path a human would: dashboard → Projects → project row →
# Open → Project Tasks → task row → Open Task Info → Kits → kit row →
# Download Transcript icon → Create. Verify the preview <pre> contains both
# segment texts and that a Download <a> with a blob: href appears.
def click_role_tab(driver, wait, text_pattern)
  wait.until do
    el = driver.find_elements(css: "[role='tab']").find { |e| e.displayed? && e.text.match?(text_pattern) }
    el&.click
    el
  end
rescue Selenium::WebDriver::Error::TimeoutError => e
  warn ""
  warn "  [DEBUG] click_role_tab(#{text_pattern.inspect}) timed out. Visible role=tab elements:"
  driver.find_elements(css: "[role='tab']").each do |t|
    next unless t.displayed?
    warn "    text=#{t.text.inspect}  state=#{t.attribute("data-state").inspect}"
  end
  raise e
end

# Find a `<td>` matching `text` that is actually visible, then click it.
# The Work tab's table stays mounted when we switch to Projects (bits-ui
# Tabs.Content keeps inactive panels in the DOM, just hidden), so a naive
# XPath would grab the hidden Work-tab td and the click would fail with
# "element not interactable". Filter by displayed?.
#
# On timeout, dump every visible table's text so we can see what the DOM
# *did* contain — narrows down "didn't navigate" vs "navigated but empty".
def click_table_cell(driver, wait, text)
  cell = wait.until do
    cells = driver.find_elements(xpath: "//table//td[normalize-space()=#{text.inspect}]")
    cells.find(&:displayed?)
  end
  driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", cell)
  cell.click
rescue Selenium::WebDriver::Error::TimeoutError => e
  warn ""
  warn "  [DEBUG] click_table_cell(#{text.inspect}) timed out. Visible tables on the page:"
  driver.find_elements(css: "table").select(&:displayed?).each_with_index do |t, i|
    warn "  --- table[#{i}] (rect=#{t.rect.x},#{t.rect.y} #{t.rect.width}x#{t.rect.height}) ---"
    warn t.text.lines.first(20).map { |l| "    #{l}" }.join
  end
  warn "  [DEBUG] current url: #{driver.current_url}"
  raise e
end

# Same idea for visible buttons: text-matched buttons may exist in inactive
# panels. Picks the first displayed one.
def click_visible_button(driver, wait, text)
  btn = wait.until do
    driver.find_elements(xpath: "//button[normalize-space()=#{text.inspect}]").find(&:displayed?)
  end
  driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", btn)
  btn.click
rescue Selenium::WebDriver::Error::TimeoutError => e
  warn ""
  warn "  [DEBUG] click_visible_button(#{text.inspect}) timed out. Visible buttons (text only):"
  driver.find_elements(css: "button").select(&:displayed?).each do |b|
    next if b.text.strip.empty?
    warn "    #{b.text.inspect}"
  end
  raise e
end

puts ""
puts "==> Sanity check before dashboard navigation:"
ctx[:project].reload
ctx[:user].reload
puts "  project ##{ctx[:project].id} '#{ctx[:project].name}' has tasks:"
ctx[:project].tasks.each { |t| puts "    ##{t.id} '#{t.name}' status=#{t.status.inspect}" }
puts "  user ##{ctx[:user].id} project_users: #{ProjectUser.where(user: ctx[:user]).pluck(:project_id, :admin, :owner).inspect}"
if ctx[:project].tasks.empty?
  abort "  FAIL: project has no tasks — the dashboard test cannot proceed."
end

puts ""
puts "==> Navigating to the dashboard to download the transcript..."
driver.navigate.to "#{TranscriptionReplLib::HOST}/users/#{ctx[:user].id}"

puts "  -> clicking [Projects] tab"
click_role_tab(driver, wait, /\AProjects\z/i)
puts "  -> clicking project row '#{ctx[:project].name}'"
click_table_cell(driver, wait, ctx[:project].name)
puts "  -> clicking [Open] button"
click_visible_button(driver, wait, "Open")

puts "  -> clicking [Project Tasks] inner tab"
click_role_tab(driver, wait, /Project Tasks/i)
puts "  -> clicking task row '#{ctx[:task].name}'"
click_table_cell(driver, wait, ctx[:task].name)
puts "  -> clicking [Open Task Info] button"
click_visible_button(driver, wait, "Open Task Info")

# Directly fetch the tasks#show JSON the same way the Svelte side does, so we
# can see what the server returns before pressing forward. If this comes back
# as { error: ... }, the .then chain in users.svelte (which iterates
# x.workflows) throws and the inner task tabs never render.
sleep 0.4
driver.manage.timeouts.script_timeout = 10
task_show_resp = driver.execute_async_script(<<~JS, ctx[:project].id, ctx[:task].id)
  const cb = arguments[arguments.length - 1];
  fetch(`/projects/${arguments[0]}/tasks/${arguments[1]}`, {
    headers: { Accept: 'application/json' }
  }).then(r => r.text()).then(t => cb({ status: 'ok', body: t })).catch(e => cb({ status: 'err', error: String(e) }));
JS
body = task_show_resp.is_a?(Hash) ? task_show_resp["body"].to_s : task_show_resp.to_s
if body.start_with?("<!DOCTYPE") || body.include?("<html")
  # Rails dev error page. The markup varies across Rails versions, so just
  # strip everything to text and pull out the heading + first "undefined
  # method" line + first few "/app/" backtrace frames.
  text = body
    .gsub(/<script.*?<\/script>/m, "")
    .gsub(/<style.*?<\/style>/m, "")
    .gsub(/<[^>]+>/, " ")
    .gsub(/&[a-z#0-9]+;/i, " ")
    .squeeze(" \n")
  # Pull the exception line and the first backtrace lines that point into the
  # app's own code (not gems).
  exception_line  = text[/(NoMethodError|NameError|ArgumentError|TypeError|RuntimeError|ActiveRecord::\S+).{0,400}/m]
  app_trace       = text.scan(%r{(?:/app/[^\s]+\.rb:\d+(?::in\s+[`'][^']+'?)?)}).first(8)
  puts "  -> /projects/#{ctx[:project].id}/tasks/#{ctx[:task].id}.json — Rails error page:"
  puts "     #{exception_line.to_s.strip[0, 500]}"
  app_trace.each { |t| puts "       #{t}" } unless app_trace.empty?
else
  puts "  -> /projects/#{ctx[:project].id}/tasks/#{ctx[:task].id}.json (first 600 chars):"
  puts "     #{body[0, 600]}"
end

puts "  -> clicking [Kits] inner tab"
click_role_tab(driver, wait, /\AKits\z/i)
# Use the source_uid column ('/test_tone_10s.wav') to pick the kit row —
# kit.id might collide with task.id or project.id text content, source_uid won't.
puts "  -> clicking kit row by source_uid '#{TranscriptionReplLib::WAV_PATH}'"
click_table_cell(driver, wait, TranscriptionReplLib::WAV_PATH)

puts "==> Opening the Download Transcript dialog..."
download_trigger = wait.until do
  driver.find_element(css: 'button:has(svg path[d^="M3 17a1 1 0 011-1h12"])')
end
download_trigger.click

# bits-ui Dialog renders into a portal at body level; multiple Dialog instances
# can coexist (Create Kits Text/File, Bulk Reassign, Download Transcript), so
# scope by the dialog whose title text contains "Download Transcript".
dialog = wait.until do
  driver.find_elements(css: "[role='dialog']").find do |d|
    d.displayed? && d.text.include?("Download Transcript")
  end
end
puts "  -> dialog opened (text starts: #{dialog.text.lines.first(2).join(' | ').strip[0, 120].inspect})"

puts "==> Filling filename, checking all three options, and clicking Create..."
filename_input = dialog.find_element(xpath: ".//input[@type='text']")
filename_input.send_keys("repl_transcript")

# Tick all three checkboxes (Include Headers / Speaker / Section). They're
# native <input type=checkbox> with `bind:checked={include_X}`, so a real
# click on each toggles the bound state. Verify each ends up :checked.
%w[include_headers include_speaker include_section].each_with_index do |label, i|
  cb = dialog.find_elements(xpath: ".//input[@type='checkbox']")[i]
  raise "expected 3 checkboxes in Download Transcript dialog, found #{i}" unless cb
  driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", cb)
  cb.click unless cb.selected?
  raise "checkbox #{label} did not become checked after click" unless cb.selected?
  puts "  -> checkbox[#{i}] (#{label}) checked"
end

# Pick the displayed "Create" button inside this dialog only.
create_btn = wait.until do
  dialog.find_elements(xpath: ".//button[normalize-space()='Create']").find(&:displayed?)
end
puts "  -> create button found: rect=#{create_btn.rect.x},#{create_btn.rect.y} #{create_btn.rect.width}x#{create_btn.rect.height} enabled=#{create_btn.enabled?}"

# Hook URL.createObjectURL BEFORE clicking Create so we can stash the Blob
# itself on window. We can't fetch the blob: URL after the fact (Selenium's
# execute_async_script context can't read blob URLs created by the page —
# both fetch and XHR fail), so we capture the original Blob object instead
# and read it via FileReader.readAsDataURL when we want its bytes.
driver.execute_script(<<~JS)
  if (!window.__origCreateObjectURL) {
    window.__origCreateObjectURL = URL.createObjectURL.bind(URL);
    URL.createObjectURL = function(blob) {
      window.__capturedBlob = blob;
      return window.__origCreateObjectURL(blob);
    };
  }
JS

# Try the normal click first; if some overlay (Dialog backdrop, tooltip)
# intercepts the click, fall back to a JS click that bypasses the synthetic
# event chain.
begin
  driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", create_btn)
  create_btn.click
rescue Selenium::WebDriver::Error::ElementClickInterceptedError, Selenium::WebDriver::Error::ElementNotInteractableError => e
  warn "  [WARN] normal click failed (#{e.class}); falling back to JS click"
  driver.execute_script("arguments[0].click();", create_btn)
end
puts "  -> create clicked"

puts "==> Waiting for transcript preview..."
# Diagnostic: directly fetch what create_download is trying to fetch, so a
# server-side exception in /kits/all (which is what feeds the preview) is
# visible in the script output rather than only in bin/repl logs.
sleep 0.5
kits_all_resp = driver.execute_async_script(<<~JS, ctx[:task].id)
  const cb = arguments[arguments.length - 1];
  fetch(`/kits/all?task_id=${arguments[0]}`, { headers: { Accept: 'application/json' } })
    .then(r => r.text()).then(t => cb({ status: 'ok', body: t })).catch(e => cb({ status: 'err', error: String(e) }));
JS
kbody = kits_all_resp.is_a?(Hash) ? kits_all_resp["body"].to_s : kits_all_resp.to_s
if kbody.start_with?("<!DOCTYPE") || kbody.include?("<html")
  text = kbody.gsub(/<script.*?<\/script>/m, "").gsub(/<style.*?<\/style>/m, "")
              .gsub(/<[^>]+>/, " ").gsub(/&[a-z#0-9]+;/i, " ").squeeze(" \n")
  exception_line = text[/(NoMethodError|NameError|ArgumentError|TypeError|RuntimeError|ActiveRecord::\S+).{0,400}/m]
  app_trace = text.scan(%r{(?:/app/[^\s]+\.rb:\d+(?::in\s+[`'][^']+'?)?)}).first(8)
  puts "  -> /kits/all?task_id=#{ctx[:task].id} — Rails error page:"
  puts "     #{exception_line.to_s.strip[0, 500]}"
  app_trace.each { |t| puts "       #{t}" }
else
  puts "  -> /kits/all?task_id=#{ctx[:task].id} (first 400 chars):"
  puts "     #{kbody[0, 400]}"
end

# Wait for the TSV preview to appear with both segment texts. textt is set
# inside the JSZip generation chain — typically <1s for our 2-segment kit.
preview = wait.until do
  pres = driver.find_elements(css: "[role='dialog'] pre")
  pres.find { |p| p.text.include?("automated first segment") && p.text.include?("automated second segment") }
end
preview_text = preview.text

# Also confirm the Download <a> got a blob: href (set inside the
# zip.generateAsync().then() callback after URL.createObjectURL).
download_link = wait.until do
  driver.find_elements(css: "[role='dialog'] a[download]").find do |a|
    a.attribute("href").to_s.start_with?("blob:")
  end
end
download_href = download_link.attribute("href")

puts ""
puts "Transcript preview (#{preview_text.length} chars):"
puts preview_text.lines.map { |l| "  #{l}" }.join
puts ""
puts "Download href: #{download_href}"

# Pull the actual zip blob the user would download, unzip it server-side, and
# print every contained file's contents. This proves the round-trip works
# end-to-end (preview text alone only proves `textt` got set; doesn't prove
# the zip was actually built and is readable).
require "base64"
require "zip"

# Read window.__capturedBlob (stashed by the URL.createObjectURL hook installed
# before the Create click). FileReader.readAsDataURL gives us a base64-encoded
# data: URL we can split the prefix off and decode in Ruby.
blob_b64 = driver.execute_async_script(<<~JS)
  const cb = arguments[arguments.length - 1];
  try {
    const blob = window.__capturedBlob;
    if (!blob) return cb('ERR:no captured blob on window');
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result || '';
      const comma = result.indexOf(',');
      cb(comma >= 0 ? result.slice(comma + 1) : ('ERR:no comma in data url ' + result.slice(0, 80)));
    };
    reader.onerror = () => cb('ERR:FileReader ' + String(reader.error));
    reader.readAsDataURL(blob);
  } catch (e) { cb('ERR:' + String(e)); }
JS

zip_entries = []
if blob_b64.is_a?(String) && !blob_b64.start_with?("ERR:")
  zip_bytes = Base64.decode64(blob_b64)
  puts ""
  puts "==> Downloaded zip blob (#{zip_bytes.bytesize} bytes). Contents:"
  Zip::File.open_buffer(zip_bytes) do |zip|
    zip.each do |entry|
      # Skip directory entries — JSZip writes a "transcripts/" folder entry
      # whose get_input_stream returns Zip::NullInputStream (a module, not an
      # io), so calling .read on it raises NoMethodError under rubyzip 3.x.
      next if entry.directory?
      content = entry.get_input_stream.read
      zip_entries << { name: entry.name, content: content }
      puts ""
      puts "── #{entry.name} (#{content.bytesize} bytes) ──"
      puts content.lines.map { |l| "  #{l}" }.join
    end
  end
else
  warn "  [WARN] failed to fetch download blob: #{blob_b64.inspect}"
end

# Build pass/fail rows for the dump_and_exit summary section.
download_passes   = []
download_failures = []
expect = ->(label, ok) { ok ? download_passes << label : download_failures << label }

expect.call("preview <pre> rendered with non-empty text",            !preview_text.empty?)
expect.call("preview includes segment 1 text 'automated first segment'",
  preview_text.include?("automated first segment"))
expect.call("preview includes segment 2 text 'automated second segment'",
  preview_text.include?("automated second segment"))
expect.call("preview includes the source file (test_tone_10s.wav)",
  preview_text.include?("test_tone_10s.wav"))
# With Include Headers + Include Speaker + Include Section all on:
#   row 1 = column headers (Kit Audio Beg End Text Speaker Section)
#   row 2 = segment 1 (with speaker Alice, no section)
#   row 3 = segment 2 (no speaker, with section "intro")
non_empty_rows = preview_text.lines.reject { |l| l.strip.empty? }.size
expect.call("preview has exactly 3 rows (header + 2 segments)",       non_empty_rows == 3)
expect.call("preview header row has Speaker and Section columns",
  preview_text.lines.first.to_s.include?("Speaker") && preview_text.lines.first.to_s.include?("Section"))
expect.call("preview shows speaker 'Alice' on segment 1",            preview_text.include?("Alice"))
expect.call("preview shows section 'intro' on segment 2",            preview_text.include?("intro"))
expect.call("Download <a> got a blob: href",                         download_href.start_with?("blob:"))
expect.call("downloaded zip has ≥1 entry",                            zip_entries.any?)
expect.call("downloaded TSV includes both segment texts",
  zip_entries.any? { |e| e[:content].include?("automated first segment") && e[:content].include?("automated second segment") })
expect.call("downloaded TSV has Alice + intro (speaker + section columns)",
  zip_entries.any? { |e| e[:content].include?("Alice") && e[:content].include?("intro") })

# ── annotation-tool TSV vs dashboard zip TSV ────────────────────────────
# Both downloads call create_transcript(kit_uid, ...) with the same flags, so
# they should be byte-for-byte identical.
downloaded_tsv = zip_entries.first&.dig(:content).to_s
ann_pass = []
ann_fail = []
expect_a = ->(label, ok) { ok ? ann_pass << label : ann_fail << label }

if ann_tool_tsv && !downloaded_tsv.empty?
  expect_a.call("annotation-tool TSV captured (non-empty)",                     !ann_tool_tsv.empty?)
  expect_a.call("annotation-tool TSV has same row count as dashboard TSV",
    ann_tool_tsv.lines.size == downloaded_tsv.lines.size)
  expect_a.call("annotation-tool TSV equals dashboard zip TSV byte-for-byte",
    ann_tool_tsv == downloaded_tsv)
  unless ann_tool_tsv == downloaded_tsv
    puts ""
    puts "  diff (— = annotation-tool, + = dashboard-zip):"
    ann_tool_tsv.lines.zip(downloaded_tsv.lines).each do |a, d|
      next if a == d
      puts "  - #{a.to_s.chomp}"
      puts "  + #{d.to_s.chomp}"
    end
  end
else
  expect_a.call("annotation-tool TSV captured (non-empty)", false)
end

# ── OnTheFly workflow smoke test ────────────────────────────────────────
# Different shape from the main flow: instead of pre-creating a Kit,
# Workflow#work → onthefly creates a kit on first /workflows/X/work visit
# (via Task#create_default_kit_with_default_doc, which reads task.meta['docid']
# for the kit's source). The user assigns it implicitly and we just hit Done.
# No annotations, no segments — we only verify the canonical OnTheFly path:
# task created, taskuser linked, kit auto-created with the right source,
# kit transitions to 'done'.
puts ""
puts "==> OnTheFly smoke test (create task → auto-create kit → mark done)"

otf_workflow = Workflow.find_by!(name: "OnTheFly")
otf_kit_type = KitType.find_by!(name: "transcription_repl")  # reuse — same constraints work
otf_task = Task.where(name: "transcription_repl_otf_task", project: ctx[:project]).first_or_create do |t|
  t.workflow = otf_workflow
  t.kit_type = otf_kit_type
  t.status   = "active"
end
# Task#use_default_doc reads meta['docid'] when the kit is auto-created, so
# we have to set it (and re-set on every run since this is the only way the
# kit gets a meaningful source under OnTheFly).
otf_task.update!(meta: (otf_task.meta || {}).merge("docid" => TranscriptionReplLib::WAV_PATH))

otf_task_user = TaskUser.where(task: otf_task, user: ctx[:user]).first_or_create
otf_task_user.update!(admin: true, state: "needs_kit", kit_oid: nil)

puts "  -> task ##{otf_task.id} '#{otf_task.name}' workflow=OnTheFly meta=#{otf_task.meta.inspect}"
puts "  -> task_user ##{otf_task_user.id}"

# Navigate to the work URL — triggers Workflow#work → onthefly →
# create_default_kit_with_default_doc → assign_kit(:skip) → goto_state has_kit.
otf_work_url = "#{TranscriptionReplLib::HOST}/workflows/#{otf_task_user.id}/work/#{otf_workflow.id}"
puts "  -> navigating to #{otf_work_url}"
driver.navigate.to otf_work_url

# Wait for the server-side assignment to land in the DB.
puts "  -> waiting for OnTheFly kit to be auto-created and assigned..."
otf_kit = nil
deadline = Time.now + 15
loop do
  otf_task_user.reload
  if otf_task_user.kit_oid.present?
    otf_kit = Kit.find_by(uid: otf_task_user.kit_oid)
    break if otf_kit && otf_kit.state == "assigned"
  end
  raise "OnTheFly kit not assigned within 15s (task_user.state=#{otf_task_user.state.inspect})" if Time.now > deadline
  sleep 0.25
end
puts "  -> OnTheFly kit ##{otf_kit.id} uid=#{otf_kit.uid.inspect} source_uid=#{otf_kit.source_uid.inspect}"

# Wait for the work page's Svelte side to mount so the close-kit ✓ button
# is rendered. Don't wait for canvas/audio — we don't care for this test.
wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }

# Click ✓ → Done in the modal — same selectors as the main flow.
puts "  -> clicking close-kit (✓) trigger and confirming Done"
otf_close_btn = wait.until { driver.find_element(css: 'button:has(svg path[d^="M10 18a8 8 0 100-16"])') }
otf_close_btn.click
otf_done_btn = wait.until { driver.find_element(xpath: "//dialog//button[contains(., 'Done')]") }
otf_done_btn.click

# Wait for kit.state = 'done'.
deadline = Time.now + 15
loop do
  break if otf_kit.reload.state == "done"
  raise "OnTheFly kit never reached 'done' (last seen #{otf_kit.state.inspect})" if Time.now > deadline
  sleep 0.25
end
puts "  -> OnTheFly kit ##{otf_kit.id} state=done"

otf_passes   = []
otf_failures = []
expect_otf = ->(label, ok) { ok ? otf_passes << label : otf_failures << label }

expect_otf.call("OnTheFly task '#{otf_task.name}' exists with workflow=OnTheFly",
  otf_task.workflow_id == otf_workflow.id)
expect_otf.call("  …task.meta['docid'] = #{TranscriptionReplLib::WAV_PATH}",
  otf_task.meta["docid"] == TranscriptionReplLib::WAV_PATH)
expect_otf.call("OnTheFly TaskUser linked",                         !TaskUser.where(task: otf_task, user: ctx[:user]).first.nil?)
expect_otf.call("OnTheFly kit auto-created on first work visit",    !otf_kit.nil?)
expect_otf.call("  …source_uid = #{TranscriptionReplLib::WAV_PATH}", otf_kit && otf_kit.source_uid == TranscriptionReplLib::WAV_PATH)
expect_otf.call("  …tree was created (Workflow#assign_kit ran the canonical path)",
  otf_kit && !otf_kit.tree_id.nil?)
expect_otf.call("OnTheFly kit reached state='done' after ✓ Done",   otf_kit && otf_kit.state == "done")
expect_otf.call("  …'done' Annotation recorded",
  otf_kit && Annotation.where(kit_id: otf_kit.id, message: "done").exists?)
# The first Annotation on the OTF kit should be the canonical 'new' marker
# from KitType#create_with_json (same as for the Orderly kit).
otf_first_ann = otf_kit ? Annotation.where(kit_id: otf_kit.id).order(:id).first : nil
expect_otf.call("  …first Annotation message='new' (tree-creation marker)",
  otf_first_ann && otf_first_ann.message == "new" && otf_first_ann.last_iid == 0)

driver.quit rescue nil

# ── the log is the record ────────────────────────────────────────────────
# The client now allocates iids and encodes the group string on the graph side
# rather than in the node layer, so what has to be proved is that the messages
# reaching the server are the same ones it always got: well-formed groups,
# every iid handed out exactly once, and a log the server can replay without
# complaint. Everything else the client believes is downstream of these rows.
log_passes = []
log_failures = []
expect_log = ->(label, ok) { ok ? log_passes << label : log_failures << label }

tree_id = ctx[:kit].reload.tree_id
adds = Annotation.where(tree_id: tree_id, message: "add").order(:id).to_a
groups = adds.map { |a| a.value.to_s }

expect_log.call("every 'add' logged a group string (#{groups.size})",
  groups.any? && groups.all? { |g| g.match?(/\A\d+:[A-Za-z]+(,\d+:[A-Za-z]+)*\z/) })

# The list item comes first and names the group; its children follow in class-def
# order. That's what NodeDerivation#apply_add reads back.
expect_log.call("each group is a list item followed by its children",
  groups.all? { |g| g.split(",").first.split(":").last.end_with?("ListItem") })

issued = groups.flat_map { |g| g.split(",").map { |pair| pair.split(":").first.to_i } }
expect_log.call("iids were issued in order, #{issued.first}–#{issued.last}",
  issued == issued.sort)
expect_log.call("no iid was issued twice",
  issued.uniq.length == issued.length)

# last_iid on each annotation is where the client said it had got to; the next
# group must start after it, or two segments would collide.
expect_log.call("each group starts after the previous last_iid",
  adds.each_cons(2).all? { |a, b| b.value.split(",").first.split(":").first.to_i > a.value.split(",").last.split(":").first.to_i })

anomalies = NodeDerivation.for_tree(tree_id).anomalies
expect_log.call("the server can replay the log with no anomalies" \
                "#{anomalies.any? ? " — #{anomalies.first(3).join("; ")}" : ""}",
  anomalies.empty?)

# And the tree those messages describe is the one the annotator made.
derived = NodeDerivation.for_tree(tree_id)
texts = derived.nodes.each_value.select { |n| n[:name] == "Text" }
              .map { |n| derived.value_for(n)[:value].to_s }.reject(&:empty?).sort
expect_log.call("the replayed tree holds both segment texts",
  texts == SEGMENTS.map { |s| s[:text] }.sort)

TranscriptionReplLib.dump_and_exit(
  kit: ctx[:kit], tree: ctx[:tree], task_user: ctx[:task_user],
  extra_checks: [
    {
      label: "Download Transcript (Projects → Tasks → Kits → Download)",
      passes: download_passes,
      failures: download_failures,
    },
    {
      label: "Annotation-tool download (in-tool ⬇ button) vs dashboard zip TSV",
      passes: ann_pass,
      failures: ann_fail,
    },
    {
      label: "Reload the work page and re-read the segments",
      passes: reload_passes,
      failures: reload_failures,
    },
    {
      label: "A selection past the end of the audio",
      passes: clamp_passes,
      failures: clamp_failures,
    },
    {
      label: "Tab from the waveform reaches the text window",
      passes: tab_passes,
      failures: tab_failures,
    },
    {
      label: "Reshaping: split, merge, delete",
      passes: shape_passes,
      failures: shape_failures,
    },
    {
      label: "The annotation log the client wrote",
      passes: log_passes,
      failures: log_failures,
    },
    {
      label: "OnTheFly workflow smoke test",
      passes: otf_passes,
      failures: otf_failures,
    },
  ],
)
