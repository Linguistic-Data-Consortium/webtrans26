#!/usr/bin/env ruby
# Drives Selection statistics (the chart button in the Controls toolbar) in a
# real browser, against a recording whose levels are known: a 440 Hz tone at
# amplitude 0.3 over noise uniform in ±0.003, the bursts preview_auto.rb uses.
#
#   tone only (1–3 s)      RMS 20·log10(0.3/√2) ≈ −13.5 dBFS, quartiles alike
#   noise only (3.2–4.8 s) RMS 20·log10(0.003/√3) ≈ −55.2 dBFS
#   half and half (0–2 s)  Q1 at the noise, Q3 at the tone, the median between
#
#   bin/repl                                   # in another terminal
#   bundle exec ruby script/stats_auto.rb      # HEADLESS=1 for no window
#
# SCREENSHOTS=1 saves the dialog to Dir.tmpdir.
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
TONE_DB = 20 * Math.log10(0.3 / Math.sqrt(2))
NOISE_DB = 20 * Math.log10(0.003 / Math.sqrt(3))

def wav_bytes
  rng = Random.new(1)
  samples = Array.new(SR * SECONDS) do |i|
    t = i.to_f / SR
    v = (rng.rand - 0.5) * 0.006
    v += 0.3 * Math.sin(2 * Math::PI * 440 * t) if BURSTS.any? { |a, b| t >= a && t < b }
    (v * 32767).round.clamp(-32768, 32767)
  end
  data = samples.pack("s<*")
  [ "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, SR, SR * 2, 2, 16, "data", data.bytesize ]
    .pack("a4Va4a4VvvVVvva4V") + data
end

NAME = "stats_bursts_20s.wav"
PUBLIC_PATH = Rails.root.join("public", NAME).to_s
File.binwrite(PUBLIC_PATH, wav_bytes)
at_exit { FileUtils.rm_f PUBLIC_PATH }

$results = []
def check(label, ok)
  $results << [ label, ok ]
  puts "  #{ok ? 'ok  ' : 'FAIL'} #{label}"
end

ctx = TranscriptionReplLib.setup_data(source_uid: "/#{NAME}", source_filename: NAME,
                                      kit_type_name: "stats_repl", name_suffix: "_stats")
driver = TranscriptionReplLib.launch_browser_signed_in(user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task])
at_exit { driver.quit rescue nil }
wait = Selenium::WebDriver::Wait.new(timeout: 30)

# The dialog's numbers for one selection: { "Median" => -13.5, … }.
def stats_for(driver, wait, beg, len)
  driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", beg, len)
  sleep 0.2
  driver.find_element(css: "[data-testid='stats-open']").click
  wait.until { driver.find_elements(css: "[data-testid='stats-table']").any?(&:displayed?) }
  driver.save_screenshot(File.join(Dir.tmpdir, "stats_dialog.png")) if ENV["SCREENSHOTS"]
  out = driver.execute_script(<<~JS)
    const out = {};
    for (const tr of document.querySelectorAll('[data-testid="stats-table"] tbody tr')) {
      const cells = tr.querySelectorAll('td');
      out[cells[0].textContent.trim()] = parseFloat(cells[1].textContent);
    }
    return out;
  JS
  driver.action.send_keys(:escape).perform
  sleep 0.3
  out
end

def near?(a, b, tol = 0.5) = (a - b).abs <= tol

begin
  wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
  sleep 0.5
  driver.find_elements(css: "[aria-label='Close guide']").find(&:displayed?)&.click

  puts "==> Tone only, 1–3 s..."
  s = stats_for(driver, wait, 1.0, 2.0)
  check "100 frames of 20 ms over 2 s (#{s['Frames (20 ms)']})", s["Frames (20 ms)"] == 100
  check "RMS at the tone's level (#{s['Level, RMS (dBFS)']} vs #{TONE_DB.round(1)})", near?(s["Level, RMS (dBFS)"], TONE_DB)
  check "peak at its amplitude (#{s['Peak (dBFS)']} vs #{(20 * Math.log10(0.3)).round(1)})", near?(s["Peak (dBFS)"], 20 * Math.log10(0.3))
  check "every quartile at the tone's level (#{%w[Q1 Median Q3].map { |k| s[k] }.inspect})",
        %w[Q1 Median Q3].all? { |k| near?(s[k], TONE_DB) }
  check "a run would see the noise as background, a margin under the threshold (#{s['Background floor (dBFS)']}, #{s['Threshold (dBFS)']})",
        near?(s["Background floor (dBFS)"], NOISE_DB, 1.0) && near?(s["Threshold (dBFS)"] - s["Background floor (dBFS)"], 10, 0.05)
  check "all of it sound, evenly (#{s['Sound: share of frames']}%, spread #{s['Sound: spread, Q3−Q1 (dB)']})",
        s["Sound: share of frames"] == 100 && s["Sound: spread, Q3−Q1 (dB)"] < 1

  puts "==> Noise only, 3.2–4.8 s..."
  s = stats_for(driver, wait, 3.2, 1.6)
  check "RMS at the noise's level (#{s['Level, RMS (dBFS)']} vs #{NOISE_DB.round(1)})", near?(s["Level, RMS (dBFS)"], NOISE_DB)
  check "the median there too (#{s['Median']})", near?(s["Median"], NOISE_DB, 1.0)
  check "no silent frames: noise isn't silence", s["Silent frames"] == 0
  check "and none of it sound to a run (#{s['Sound: share of frames']}%)", s["Sound: share of frames"] == 0

  puts "==> Half and half, 0–2 s..."
  s = stats_for(driver, wait, 0.0, 2.0)
  check "Q1 at the noise, Q3 at the tone, the median between (#{%w[Q1 Median Q3].map { |k| s[k] }.inspect})",
        near?(s["Q1"], NOISE_DB, 1.0) && near?(s["Q3"], TONE_DB) && s["Median"] > s["Q1"] + 10 && s["Median"] < s["Q3"] - 10

rescue => e
  check "no exception (#{e.class}: #{e.message.lines.first&.strip})", false
end

failed = $results.reject(&:last)
puts ""
puts failed.empty? ? "PASS — #{$results.size} checks" : "FAIL — #{failed.size} of #{$results.size} checks failed"
exit(failed.empty? ? 0 : 1)
