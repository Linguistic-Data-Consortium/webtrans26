#!/usr/bin/env ruby
# Drives Delete all in a real browser and checks the blue underlines under the
# waveform go with the segments — they're drawn from their own store
# (sourcesor), which only the single-segment delete used to clear.
#
#   1. Three segments: three underlines.
#   2. One deleted on its own: two.
#   3. Delete all, through its dialog: none, and no rows.
#   4. A reload: still none.
#
#   bin/repl                                         # in another terminal
#   bundle exec ruby script/delete_all_auto.rb       # HEADLESS=1 for no window
#
# Exit 0 = PASS, 1 = FAIL.

ENV["RAILS_ENV"] ||= "repl"

require_relative "transcription_repl_lib"

TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

$results = []
def check(label, ok)
  $results << [ label, ok ]
  puts "  #{ok ? 'ok  ' : 'FAIL'} #{label}"
end

ctx = TranscriptionReplLib.setup_data
driver = TranscriptionReplLib.launch_browser_signed_in(user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task])
at_exit { driver.quit rescue nil }
wait = Selenium::WebDriver::Wait.new(timeout: 30)

def underlines(driver) = driver.execute_script("return document.querySelectorAll('[class^=\"underlines\"] .bg-blue-700').length")
def rows(driver) = driver.find_elements(css: "#segments .segment").size

def wait_for_tool(driver, wait)
  wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
  sleep 0.5
end

begin
  wait_for_tool(driver, wait)
  driver.find_elements(css: "[aria-label='Close guide']").find(&:displayed?)&.click

  puts "==> Three segments..."
  [ [ 0.5, 1.0 ], [ 2.0, 1.0 ], [ 4.0, 1.0 ] ].each do |beg, len|
    driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", beg, len)
    sleep 0.2
    n = rows(driver)
    k = driver.find_element(css: ".keyboard")
    k.click
    k.send_keys(:enter)
    wait.until { rows(driver) == n + 1 }
    sleep 0.6
  end
  check "three rows, three underlines (#{underlines(driver)})", rows(driver) == 3 && underlines(driver) == 3

  puts "==> Deleting one on its own..."
  ta = wait.until { driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment") }
  ta.click
  driver.execute_script(<<~JS)
    const ta = document.querySelector('#segments .segment.active-segment textarea.ann-segment');
    ta.dispatchEvent(new KeyboardEvent('keydown', { key: 'd', code: 'KeyD', ctrlKey: true, bubbles: true, cancelable: true }));
  JS
  confirm = wait.until { driver.find_elements(css: "#segments button").find { |b| b.displayed? && b.text.strip.match?(/delete/i) } }
  confirm.click
  wait.until { rows(driver) == 2 }
  sleep 0.6
  check "two rows, two underlines (#{underlines(driver)})", underlines(driver) == 2

  puts "==> Delete all..."
  driver.execute_script("[...document.querySelectorAll('dialog')].find(d => d.textContent.includes('Delete ALL Segments')).showModal()")
  dialog = wait.until { driver.find_elements(css: "dialog[open]").find { |d| d.text.include?("Delete ALL Segments") } }
  dialog.find_element(xpath: ".//button[normalize-space()='Delete All']").click
  wait.until { rows(driver) == 0 }
  sleep 1.5
  check "no rows, and no underlines left (#{underlines(driver)})", underlines(driver) == 0

  puts "==> Reloading..."
  driver.navigate.refresh
  wait_for_tool(driver, wait)
  sleep 1
  check "still none (#{rows(driver)} rows, #{underlines(driver)} underlines)", rows(driver) == 0 && underlines(driver) == 0
rescue => e
  check "no exception (#{e.class}: #{e.message.lines.first&.strip})", false
end

failed = $results.reject(&:last)
puts ""
puts failed.empty? ? "PASS — #{$results.size} checks" : "FAIL — #{failed.size} of #{$results.size} checks failed"
exit(failed.empty? ? 0 : 1)
