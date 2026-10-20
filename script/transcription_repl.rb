#!/usr/bin/env ruby
# Interactive harness for the transcription tool.
#
# Runs against an isolated `repl` Rails environment with its own SQLite DB
# (storage/repl.sqlite3) on port 3001 — won't touch dev or test data.
#
#   1. Start the repl server in another terminal:
#         bin/repl
#      (which is RAILS_ENV=repl TRANSCRIPTION_REPL=1 bin/rails server -p 3001;
#       TRANSCRIPTION_REPL=1 enables config/initializers/transcription_repl_patch.rb
#       so the work-page audio manifest points at public/test_tone_10s.wav.)
#
#   2. Run this script:
#         bundle exec ruby script/transcription_repl.rb
#
#   3. A real Chrome window opens, pre-logged-in, on the work page for a fresh kit
#      whose source is `/test_tone_10s.wav` (10-second 1 kHz sine tone). Make
#      annotations, then close the window.
#
#   4. Script dumps the kit's annotations, nodes, kit/task_user state, and KitState
#      transitions to stdout, then runs structural assertions (PASS/FAIL).
#
# Set DUMP_ALL=1 to also print SELECT * over every table in the DB before the
# assertions run — handy for diagnosing why an assertion failed.
#
# For the fully-automated variant (no human required), see script/transcription_auto.rb.

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

puts ""
puts "==> Browser is open. Make some annotations on the WAV in the transcription UI."
puts "==> Close the browser window when you're done."

TranscriptionReplLib.wait_for_browser_close(driver)

TranscriptionReplLib.dump_and_exit(kit: ctx[:kit], tree: ctx[:tree], task_user: ctx[:task_user])
