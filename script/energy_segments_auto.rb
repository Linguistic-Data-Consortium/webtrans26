#!/usr/bin/env ruby
# Drives "Segments from sound level" (Services menu, entry 6) in a real
# browser, against a recording whose answer is known: tone bursts over quiet
# noise, generated here.
#
#   1–3 s     a segment
#   5–5.5 s   a short one, still long enough to keep
#   8–12 s    already covered by a segment made by hand at 9–10 s: skipped
#   15–16.2 s and 16.4–17 s   a 0.2 s pause, too short to split on: one segment
#   18–18.1 s a click, too short to keep
#   18.5–19.9 s a click train — 3 ms clicks every 120 ms — joined across its
#             gaps into one long stretch that is mostly background: rejected
#             as clicks rather than kept as a segment
#
# With the default settings that is three new segments, padded 0.1 s:
# 0.9–3.1, 4.9–5.6 and 14.9–17.1. Checked on screen, and again after a
# reload, which rebuilds the rows from the annotation log.
#
# Run twice: a kit whose audio the server serves, and a local_audio kit whose
# file is picked from disk — the two ways the audio is read.
#
#   bin/repl                                              # in another terminal
#   bundle exec ruby script/energy_segments_auto.rb       # HEADLESS=1 for no window
#
# Exit 0 = PASS, 1 = FAIL.

ENV["RAILS_ENV"] ||= "repl"

require_relative "transcription_repl_lib"
require "fileutils"

TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

SR = 16000
SECONDS = 20
BURSTS = [ [ 1, 3 ], [ 5, 5.5 ], [ 8, 12 ], [ 15, 16.2 ], [ 16.4, 17 ], [ 18, 18.1 ] ].freeze
CLICKS = (0..11).map { |k| 18.5 + 0.12 * k }.freeze   # 3 ms each
EXPECTED = [ [ 0.9, 3.1 ], [ 4.9, 5.6 ], [ 14.9, 17.1 ] ].freeze
HAND_MADE = [ 9.0, 10.0 ].freeze

def wav_bytes
  rng = Random.new(1)
  samples = Array.new(SR * SECONDS) do |i|
    t = i.to_f / SR
    loud = BURSTS.any? { |a, b| t >= a && t < b }
    v = (rng.rand - 0.5) * 0.006
    v += 0.3 * Math.sin(2 * Math::PI * 440 * t) if loud
    v += (i.even? ? 0.3 : -0.3) if CLICKS.any? { |c| t >= c && t < c + 0.003 }
    (v * 32767).round.clamp(-32768, 32767)
  end
  data = samples.pack("s<*")
  [ "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, SR, SR * 2, 2, 16, "data", data.bytesize ]
    .pack("a4Va4a4VvvVVvva4V") + data
end

NAME = "energy_bursts_20s.wav"
PUBLIC_PATH = Rails.root.join("public", NAME).to_s
dir = Dir.mktmpdir("energy_segments_auto")
LOCAL_PATH = File.join(dir, NAME)
bytes = wav_bytes
File.binwrite(PUBLIC_PATH, bytes)
File.binwrite(LOCAL_PATH, bytes)
at_exit { FileUtils.rm_f PUBLIC_PATH; FileUtils.rm_rf dir }

$results = []
def check(label, ok)
  $results << [ label, ok ]
  puts "  #{ok ? 'ok  ' : 'FAIL'} #{label}"
end

def wait_for_tool(driver, wait)
  wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
  sleep 0.5
end

# [beg, end] of each segment row, read off the row's text ("… 1.000 2.500 …").
def rows(driver)
  driver.execute_script(<<~JS).map { |a| a.map(&:to_f) }
    return [...document.querySelectorAll('#segments .segment')].map(s => {
      const m = s.textContent.match(/(\\d+\\.\\d{3})\\s+(\\d+\\.\\d{3})/);
      return m ? [m[1], m[2]] : null;
    }).filter(Boolean);
  JS
end

def close?(a, b) = (a[0] - b[0]).abs < 0.025 && (a[1] - b[1]).abs < 0.025

def run(mode)
  puts ""
  puts "=================== #{mode} ==================="
  if mode == :served
    ctx = TranscriptionReplLib.setup_data(source_uid: "/#{NAME}", source_filename: NAME,
                                          kit_type_name: "energy_repl", name_suffix: "_energy")
  else
    ctx = TranscriptionReplLib.setup_data(kit_type_name: "energy_local_repl", name_suffix: "_energy_local",
                                          extra_constraints: { "local_audio" => "local_audio" })
    ctx[:task].update!(workflow: Workflow.find_by!(name: "OnTheFly"))
    Kit.where(task: ctx[:task]).destroy_all
    ctx[:task_user].update!(state: "needs_kit", kit_oid: nil)
  end
  driver = TranscriptionReplLib.launch_browser_signed_in(user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task].reload)
  wait = Selenium::WebDriver::Wait.new(timeout: 30)
  # Console errors and rejections, reported if a check times out.
  driver.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
    window.__errs = [];
    const ce = console.error.bind(console);
    console.error = (...a) => { window.__errs.push(a.map(String).join(' ')); ce(...a); };
    addEventListener('error', (e) => window.__errs.push('error: ' + e.message));
    addEventListener('unhandledrejection', (e) => window.__errs.push('rejection: ' + (e.reason && (e.reason.stack || e.reason.message) || e.reason)));
  JS
  driver.navigate.refresh if mode == :served
  if mode == :local
    # The plain input: this run is about the segmenter, not the handle path.
    driver.execute_cdp("Page.addScriptToEvaluateOnNewDocument",
                       source: "try { delete Window.prototype.showOpenFilePicker; } catch (e) {} window.showOpenFilePicker = undefined;")
    driver.navigate.refresh
    wait.until { driver.find_element(css: "[data-testid='local-audio-input']") }.send_keys(LOCAL_PATH)
  end
  wait_for_tool(driver, wait)
  driver.find_elements(css: "[aria-label='Close guide']").find(&:displayed?)&.click

  puts "==> A segment by hand at #{HAND_MADE.join('–')} s..."
  keyboard = driver.find_element(css: ".keyboard")
  driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", HAND_MADE[0], HAND_MADE[1] - HAND_MADE[0])
  sleep 0.2
  keyboard.click
  keyboard.send_keys(:enter)
  textarea = wait.until { driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment") }
  textarea.send_keys("by hand")
  textarea.send_keys(:tab)
  sleep 1

  puts "==> Services → 6..."
  driver.execute_script(<<~JS)
    [...document.querySelectorAll('dialog')].find(x => x.textContent.includes('Available Services')).showModal();
  JS
  sleep 0.3
  text = driver.execute_script("return [...document.querySelectorAll('dialog[open]')].map(d => d.textContent).join(' ')")
  check "the Services menu offers segments from sound level", text.include?("Segments from sound level")
  driver.execute_script(<<~JS)
    const d = [...document.querySelectorAll('dialog[open]')].find(x => x.textContent.includes('Available Services'));
    d.querySelector('[tabindex="0"]').dispatchEvent(new KeyboardEvent('keydown', { key: '6', bubbles: true, cancelable: true }));
  JS
  wait.until { driver.find_elements(css: "[data-testid='energy-dialog']").any?(&:displayed?) }
  check "6 opens its settings", true
  driver.find_element(xpath: "//button[normalize-space()='Defaults']").click
  # The stretch prefills from the selection, which is still the hand-made
  # segment. Emptied the way a person would: element.clear() fires no input
  # event, so Svelte's binding would keep the old value.
  %w[energy-beg energy-end].each do |id|
    f = driver.find_element(css: "[data-testid='#{id}']")
    f.click
    f.send_keys([ :command, "a" ], :backspace)
    f.send_keys([ :control, "a" ], :backspace)
  end
  driver.find_element(css: "[data-testid='energy-run']").click

  # The run's progress is in the panel where the transcript is, and how it
  # went is a toast — no dialog over the page.
  summary = wait.until { driver.find_elements(css: "[data-sonner-toast]").find { |t| t.text.include?("Sound level —") } }
  wait.until { driver.execute_script("return [...document.querySelectorAll('#segments .segment')].length") >= 4 }
  sleep 1.5
  check "no dialog opened over the page", driver.find_elements(css: "dialog[open]").none? { |d| d.text.include?("Automatic Speech Recognition") }
  check "the summary reports what it found and skipped (#{summary.text.inspect})",
        summary.text.include?("found 4") && summary.text.include?("skipped 1")
  check "and that the click train was rejected as clicks", summary.text.include?("rejected 1 as mostly background")
  driver.action.send_keys(:escape).perform rescue nil

  found = rows(driver)
  puts "  rows: #{found.inspect}"
  EXPECTED.each { |e| check "a segment at #{e.join('–')}", found.any? { |r| close?(r, e) } }
  check "the hand-made segment is still there, and nothing was added over it",
        found.count { |r| r[0] < 12.1 && r[1] > 7.9 } == 1 && found.any? { |r| close?(r, HAND_MADE) }
  check "the click at 18 s and the click train made nothing", found.none? { |r| r[0] > 17.5 }
  check "four rows in all: three found, one by hand", found.size == 4

  puts "==> Reloading..."
  driver.navigate.refresh
  wait.until { driver.find_element(css: "[data-testid='local-audio-input']") }.send_keys(LOCAL_PATH) if mode == :local
  wait_for_tool(driver, wait)
  again = rows(driver)
  check "the same rows come back from the server (#{again.inspect})",
        again.size == found.size && again.zip(found.sort).all? { |a, b| close?(a, b) }
rescue => e
  check "no exception (#{e.class}: #{e.message.lines.first&.strip})", false
  errs = (driver.execute_script("return window.__errs || []") rescue [])
  puts "  page errors:", errs.last(10).map { |x| "    #{x[0, 400]}" } if errs.any?
  dialogs = (driver.execute_script("return [...document.querySelectorAll('dialog[open]')].map(d => d.innerText).join(' || ')") rescue "")
  puts "  open dialogs: #{dialogs[0, 600]}" unless dialogs.to_s.empty?
ensure
  driver&.quit rescue nil
end

(ENV["MODE"] ? [ ENV["MODE"].to_sym ] : [ :served, :local ]).each { |m| run(m) }

failed = $results.reject(&:last)
puts ""
puts failed.empty? ? "PASS — #{$results.size} checks" : "FAIL — #{failed.size} of #{$results.size} checks failed"
exit(failed.empty? ? 0 : 1)
