#!/usr/bin/env ruby
# JSON-wrapper variant of script/transcription_repl.rb (the interactive harness).
#
# Same as transcription_repl.rb, but the kit's source is a JSON *wrapper*
# (public/test_tone_10s.json) that points at the audio AND a TSV transcript
# (public/test_tone_10s.tsv). With `import_transcript_auto` set, the tool opens
# the Upload Transcript dialog on load with the transcript pre-parsed, so you can
# see it pre-populated.
#
#   1. Start the repl server in another terminal:
#         bin/repl
#
#   2. Run this script:
#         bundle exec ruby script/transcription_repl_wrapper.rb
#
#   3. A real Chrome window opens, pre-logged-in, on the work page for a fresh kit
#      whose source is the JSON wrapper. The script clicks "Add with Blanks", which
#      loads the read-only reference segments AND creates matching empty editable
#      segments at the same timestamps. Fill in / edit the empty segments by hand,
#      then close the window.
#
#   4. Script dumps the kit's annotations, nodes, kit/task_user state, and KitState
#      transitions to stdout (informational — the read-only reference writes nothing;
#      the empty editable segments you filled in are persisted as normal annotations).
#
# Set DUMP_ALL=1 to also print SELECT * over every table in the DB.

ENV["RAILS_ENV"] ||= "repl"

require_relative "transcription_repl_lib"

TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

puts "==> Setting up data (JSON-wrapper kit)..."
ctx = TranscriptionReplLib.setup_data(
  source_uid: TranscriptionReplLib::WRAPPER_JSON_PATH,
  source_filename: "test_tone_10s.json",
  kit_type_name: "transcription_repl_wrapper",
  name_suffix: "_wrapper",
  extra_constraints: { "import_transcript_auto" => "import_transcript_auto" },
)

puts ""
puts "==> Launching Chrome..."
driver = TranscriptionReplLib.launch_browser_signed_in(
  user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task]
)
at_exit { driver.quit rescue nil }

# ── pre-populate: load the transcript ──────────────────────────────────────
# Click "Add with Blanks" to load the transcript: the app loads the read-only
# reference segments AND creates matching empty editable segments at the same
# timestamps (waveform.svelte:update_segments2_with_blanks), so you can fill in the
# true transcript. Best-effort: if any step fails we warn and still hand over.
wait = Selenium::WebDriver::Wait.new(timeout: 30)
begin
  puts ""
  puts "==> Waiting for transcription tool to mount..."
  wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }

  # The dialog auto-opens via import_transcript_auto; if it doesn't, trigger it.
  puts "==> Loading the transcript (Add with Blanks)..."
  find_add_btn = lambda do
    dlg = driver.find_elements(css: "dialog[open]").find { |d| d.displayed? && d.text.include?("Upload Transcript") }
    dlg && dlg.find_elements(xpath: ".//button[normalize-space()='Add with Blanks']").find(&:displayed?)
  end
  add_btn =
    begin
      Selenium::WebDriver::Wait.new(timeout: 8).until { find_add_btn.call }
    rescue Selenium::WebDriver::Error::TimeoutError
      driver.execute_script("window.ldc.wc.trigger_import_transcript()")
      wait.until { find_add_btn.call }
    end
  add_btn.click
  # Close the modal <dialog> so keyboard/waveform gestures reach the tool.
  driver.execute_script("document.querySelectorAll('dialog[open]').forEach(d => d.close());")
  wait.until { driver.find_elements(css: "#segments .segment").any? }
  puts "  -> transcript loaded (read-only reference + matching empty editable segments)"
rescue => e
  warn "  [warn] pre-population step failed (#{e.class}: #{e.message}); handing the browser over anyway."
end

puts ""
puts "==> Browser is open, pre-populated with the read-only reference transcript and"
puts "==> matching empty editable segments at the same timestamps. Fill them in / edit"
puts "==> as you like, then close the browser window when you're done."

TranscriptionReplLib.wait_for_browser_close(driver)

# Informational dump only. Unlike transcription_repl.rb we don't run
# dump_and_exit's structural checks: they assert the plain fixture names and a
# created-from-scratch transcript, whereas this kit uses the *_wrapper fixtures
# and (via "Add Read Only") may legitimately write nothing to the DB.
TranscriptionReplLib.dump_state(kit: ctx[:kit], tree: ctx[:tree], task_user: ctx[:task_user])

puts ""
puts "==> Done (informational dump above). Run the script again to start a fresh kit/tree."
