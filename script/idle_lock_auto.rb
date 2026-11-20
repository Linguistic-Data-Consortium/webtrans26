#!/usr/bin/env ruby
# The screen lock in the editor: a line typed and left in its field, with no
# further input, must be saved before the lock clears the page (idle_lock.js
# blurs the field, which saves it, and waits for the save).
#
# Needs a repl server started with a short limit, e.g.
#   SESSION_IDLE_MINUTES=0.15 bin/repl      # 9 seconds
#   bundle exec ruby script/idle_lock_auto.rb
#
# Exit 0 = PASS, 1 = FAIL. HEADLESS=1 to keep the window out of the way.

ENV["RAILS_ENV"] ||= "repl"
require_relative "transcription_repl_lib"
TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

ctx = TranscriptionReplLib.setup_data(name_suffix: "_idle")
earlier_sessions = ctx[:user].sessions.pluck(:id) # from earlier runs, untouched by this one
driver = TranscriptionReplLib.launch_browser_signed_in(user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task])
at_exit { driver.quit rescue nil }
wait = Selenium::WebDriver::Wait.new(timeout: 30)
ok = []
check = ->(label, pass) { ok << pass; puts "  #{pass ? 'ok  ' : 'FAIL'} #{label}" }

wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
sleep 0.5
kit = ctx[:kit].reload

puts "==> A line typed and left in its field"
driver.execute_script("window.ldc.wc.set_current_selection(0.5, 1.5)")
sleep 0.2
driver.find_element(css: ".keyboard").click
driver.find_element(css: ".keyboard").send_keys(:enter)
ta = wait.until { driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment") }
ta.send_keys("left unsaved when the screen locked")
check.("not saved yet, while the field has focus",
       Annotation.where(kit_id: kit.id, message: "change").none? { |a| a.value.to_s.include?("left unsaved") })

puts "==> No input until the lock"
Selenium::WebDriver::Wait.new(timeout: 60).until { driver.current_url.include?("/session/new") }
check.("the page was replaced by sign-in", driver.current_url.include?("idle=1"))
check.("the line was saved before it cleared",
       Annotation.where(kit_id: kit.id, message: "change").any? { |a| a.value.to_s.include?("left unsaved when the screen locked") })
this_session = Session.where(user_id: ctx[:user].id).where.not(id: earlier_sessions)
check.("this browser's session ended on the server", this_session.none?)

puts ok.all? ? "==> PASS — #{ok.size} checks." : "==> FAIL — #{ok.count(false)} of #{ok.size} failed."
exit(ok.all? ? 0 : 1)
