#!/usr/bin/env ruby
# What happens to an edit made after the session has ended, in the real tool.
#
# The editor saves each change after showing it, so a save refused because the
# session has ended must neither vanish nor stop the saves behind it. The tool
# holds it, says so (session_banner.svelte), and sends it once the user has
# signed in again from another tab (modification2.js save_failed,
# session_hold.svelte.js). This drives exactly that:
#
#   1. type a segment and see it saved, as usual
#   2. end the session server-side, as SESSION_IDLE_MINUTES without use would
#   3. add a segment: the banner appears and nothing reaches the log
#   4. sign in again in a second tab, then press "I've signed in"
#   5. the held add lands, the segment becomes typeable, and its text saves too
#
#   bin/repl                                   # in another terminal
#   bundle exec ruby script/session_expiry_auto.rb
#
# Exit 0 = PASS, 1 = FAIL. HEADLESS=1 to keep the browser window out of the way.

ENV["RAILS_ENV"] ||= "repl"

require_relative "transcription_repl_lib"

TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

ctx = TranscriptionReplLib.setup_data(name_suffix: "_expiry")
driver = TranscriptionReplLib.launch_browser_signed_in(user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task])
at_exit { driver.quit rescue nil }
wait = Selenium::WebDriver::Wait.new(timeout: 30)
checks = []
check = lambda do |label, ok|
  checks << ok
  puts "  #{ok ? 'ok  ' : 'FAIL'} #{label}"
end

wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
sleep 0.5
kit = ctx[:kit].reload
keyboard = driver.find_element(css: ".keyboard")

annotations = ->(message) { Annotation.where(kit_id: kit.id, message: message) }
texts = -> { annotations.("change").filter_map(&:value) }
# A new segment is three adds (its two anchors and itself); count the segments.
segments = -> { annotations.("add").count { |a| a.value.to_s.include?("SegmentListItem") } }

# Select audio, press Enter for a new segment, and wait for it to be the
# active one: the tool makes it typeable only once the server has answered.
add_segment = lambda do |beg|
  driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", beg, 1.5)
  sleep 0.2
  keyboard.click
  keyboard.send_keys(:enter)
end
type_into_active = lambda do |text|
  ta = wait.until { driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment") }
  ta.send_keys(text)
  driver.execute_script("document.activeElement.blur()") # onblur saves the text
end
# Asked of the page itself: the banner can go between finding it and asking.
banner = -> { driver.execute_script("return !!document.getElementById('session-hold-banner')") }
out_of_step = -> { driver.page_source.include?("out of step with the server") }

puts "==> 1. A segment saved as usual"
add_segment.(0.5)
wait.until { driver.find_elements(css: "#segments .segment.active-segment").any? }
type_into_active.("typed while signed in")
wait.until { texts.().any? { |v| v.include?("typed while signed in") } }
check.("its text is in the log", true)
segments_before = segments.()

puts "==> 2. The session ends (as after SESSION_IDLE_MINUTES without use)"
ctx[:user].sessions.update_all(updated_at: 3.hours.ago)

puts "==> 3. A segment added while signed out"
add_segment.(3.0)
wait.until { banner.() }
check.("the signed-out banner shows", banner.())
sleep 2
check.("nothing reached the log", segments.() == segments_before)
check.("no 'out of step' banner", !out_of_step.())

puts "==> 4. Sign in again in another tab"
tool = driver.window_handle
driver.switch_to.new_window(:tab)
driver.navigate.to "#{TranscriptionReplLib::HOST}/session/new"
driver.find_element(name: "email_address").send_keys(ctx[:user].email_address)
driver.find_element(name: "password").send_keys(TranscriptionReplLib::PASSWORD)
driver.find_element(name: "commit").click
wait.until { !driver.current_url.include?("/session/new") }
driver.close
driver.switch_to.window(tool)
driver.find_elements(css: "#session-hold-banner button").find { |b| b.text.include?("signed in") }&.click

puts "==> 5. The held save goes through, and work carries on"
wait.until { !banner.() }
check.("the banner is gone", !banner.())
wait.until { segments.() == segments_before + 1 }
check.("the held add is in the log", true)
type_into_active.("typed after signing in again")
wait.until { texts.().any? { |v| v.include?("typed after signing in again") } }
check.("the new segment's text saved", true)
check.("still no 'out of step' banner", !out_of_step.())

if checks.all?
  puts "==> PASS — #{checks.size} checks."
  exit 0
else
  puts "==> FAIL — #{checks.count(false)} of #{checks.size} checks failed."
  exit 1
end
