#!/usr/bin/env ruby
# Drives span layers as previews (PreviewLane, span_layers.svelte.js) in a real
# browser, against tone bursts at known times — the recording
# energy_segments_auto.rb uses, with a segment made by hand at 9–10 s.
#
#   1. Services 6 → Preview, twice with different settings: two layers in the
#      lane, and nothing in the annotation log.
#   2. Only the spans in the waveform window are drawn.
#   3. A reload brings both layers back.
#   4. Hiding a layer hides its spans.
#   5. A span selected in the lane, added alone; then a whole layer added,
#      gap-filling — what overlaps the hand-made segment, or the span just
#      added, is skipped.
#   6. Removing a layer; clearing the kit's previews from Downloaded resources.
#
#   bin/repl                                      # in another terminal
#   bundle exec ruby script/preview_auto.rb       # HEADLESS=1 for no window
#
# SCREENSHOTS=1 saves the lane with both layers to Dir.tmpdir.
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
HAND_MADE = [ 9.0, 10.0 ].freeze
# With the default settings: four spans, padded 0.1 s.
DEFAULT_SPANS = [ [ 0.9, 3.1 ], [ 4.9, 5.6 ], [ 7.9, 12.1 ], [ 14.9, 17.1 ] ].freeze

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

NAME = "preview_bursts_20s.wav"
PUBLIC_PATH = Rails.root.join("public", NAME).to_s
File.binwrite(PUBLIC_PATH, wav_bytes)
at_exit { FileUtils.rm_f PUBLIC_PATH }

$results = []
def check(label, ok)
  $results << [ label, ok ]
  puts "  #{ok ? 'ok  ' : 'FAIL'} #{label}"
end

ctx = TranscriptionReplLib.setup_data(source_uid: "/#{NAME}", source_filename: NAME,
                                      kit_type_name: "preview_repl", name_suffix: "_preview")
driver = TranscriptionReplLib.launch_browser_signed_in(user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task])
at_exit { driver.quit rescue nil }
wait = Selenium::WebDriver::Wait.new(timeout: 30)

def wait_for_tool(driver, wait)
  wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
  sleep 0.5
end

def rows(driver)
  driver.execute_script(<<~JS).map { |a| a.map(&:to_f) }
    return [...document.querySelectorAll('#segments .segment')].map(s => {
      const m = s.textContent.match(/(\\d+\\.\\d{3})\\s+(\\d+\\.\\d{3})/);
      return m ? [m[1], m[2]] : null;
    }).filter(Boolean);
  JS
end

def close?(a, b) = (a[0] - b[0]).abs < 0.025 && (a[1] - b[1]).abs < 0.025

# What the browser has kept for this kit: [ [ label, [ [beg, end], … ] ] ].
def stored(driver)
  driver.execute_async_script(<<~JS)
    const done = arguments[arguments.length - 1];
    const r = indexedDB.open('span_layers', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('layers');
    r.onsuccess = () => {
      const q = r.result.transaction('layers').objectStore('layers').get(window.ldc.obj2._id);
      q.onsuccess = () => { r.result.close(); done((q.result || []).map(l => [l.label, l.segments.map(s => [s.beg, s.end])])); };
    };
  JS
end

def drawn(driver)
  driver.find_elements(css: "[data-testid='preview-layer']").size.times.map do |n|
    driver.execute_script(<<~JS, n).map { |a| a.map(&:to_f) }
      const lane = document.querySelector('[data-testid="preview-lane"]');
      const layers = [...lane.querySelectorAll('[data-testid="preview-layer"]')];
      // the bars after this layer's header, up to the next header
      const out = [];
      let el = layers[arguments[0]].nextElementSibling;
      while (el && el.dataset.testid !== 'preview-layer' && el.dataset.testid !== 'preview-selected') {
        for (const b of el.querySelectorAll('[data-testid="preview-span"]')) out.push([b.dataset.beg, b.dataset.end]);
        el = el.nextElementSibling;
      }
      return out;
    JS
  end
end

def kit_changes(ctx)
  kit = Kit.where(task: ctx[:task]).order(:id).last
  Annotation.where(tree_id: kit.tree_id).count
end

def open_energy(driver, wait)
  driver.execute_script("[...document.querySelectorAll('dialog')].find(x => x.textContent.includes('Available Services')).showModal();")
  sleep 0.3
  driver.execute_script(<<~JS)
    const d = [...document.querySelectorAll('dialog[open]')].find(x => x.textContent.includes('Available Services'));
    d.querySelector('[tabindex="0"]').dispatchEvent(new KeyboardEvent('keydown', { key: '6', bubbles: true, cancelable: true }));
  JS
  wait.until { driver.find_elements(css: "[data-testid='energy-dialog']").any?(&:displayed?) }
  driver.find_element(xpath: "//button[normalize-space()='Defaults']").click
  # Emptied the way a person would; clear() fires no input event.
  %w[energy-beg energy-end].each do |id|
    f = driver.find_element(css: "[data-testid='#{id}']")
    f.click
    f.send_keys([ :command, "a" ], :backspace)
    f.send_keys([ :control, "a" ], :backspace)
  end
end

def set_field(driver, id, value)
  f = driver.find_element(css: "[data-testid='#{id}']")
  f.click
  f.send_keys([ :command, "a" ], :backspace)
  f.send_keys([ :control, "a" ], :backspace)
  f.send_keys(value)
end

begin
  wait_for_tool(driver, wait)
  driver.find_elements(css: "[aria-label='Close guide']").find(&:displayed?)&.click
  driver.execute_script("indexedDB.deleteDatabase('span_layers')")

  puts "==> A segment by hand at #{HAND_MADE.join('–')} s..."
  driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", HAND_MADE[0], HAND_MADE[1] - HAND_MADE[0])
  sleep 0.2
  keyboard = driver.find_element(css: ".keyboard")
  keyboard.click
  keyboard.send_keys(:enter)
  wait.until { rows(driver).size == 1 }
  sleep 1
  before = kit_changes(ctx)

  puts "==> Preview with the defaults..."
  open_energy(driver, wait)
  driver.find_element(css: "[data-testid='energy-preview']").click
  wait.until { driver.find_elements(css: "[data-testid='preview-layer']").size == 1 }
  sleep 0.5
  s = stored(driver)
  check "a layer, with the spans the defaults find (#{s.dig(0, 1).inspect})",
        s.size == 1 && s[0][1].size == 4 && s[0][1].zip(DEFAULT_SPANS).all? { |a, b| close?(a, b) }
  d = drawn(driver)[0]
  check "only the spans in the window (0–10 s) are drawn (#{d.inspect})", d.size == 3 && d.all? { |b, _| b < 10 }

  puts "==> A second preview: shortest pause 0.1 s..."
  open_energy(driver, wait)
  set_field(driver, "energy-min_silence", "0.1")
  driver.find_element(css: "[data-testid='energy-preview']").click
  wait.until { driver.find_elements(css: "[data-testid='preview-layer']").size == 2 }
  sleep 0.5
  s = stored(driver)
  check "a second layer, the 0.2 s pause now splitting one span in two (#{s.dig(1, 1)&.size.inspect} spans)", s[1][1].size == 5
  check "named by their settings (#{s.map(&:first).inspect})", s[0][0].include?("pause 0.3 s") && s[1][0].include?("pause 0.1 s")
  check "nothing reached the annotation log", kit_changes(ctx) == before && rows(driver).size == 1
  driver.save_screenshot(File.join(Dir.tmpdir, "preview_lane.png")) if ENV["SCREENSHOTS"]

  puts "==> Reloading..."
  driver.navigate.refresh
  wait_for_tool(driver, wait)
  wait.until { driver.find_elements(css: "[data-testid='preview-layer']").size == 2 }
  check "both layers come back", true

  puts "==> Hiding the second..."
  driver.find_elements(css: "[data-testid='preview-toggle']")[1].click
  sleep 0.3
  check "its spans are hidden, the first's still drawn", drawn(driver)[1].empty? && drawn(driver)[0].size == 3

  puts "==> Adding one span..."
  span = driver.find_elements(css: "[data-testid='preview-span']").find { |b| (b.attribute("data-beg").to_f - 4.9).abs < 0.025 }
  span.click
  sel = wait.until { driver.find_element(css: "[data-testid='preview-selected']") }
  check "selecting it shows it (#{sel.text.lines.first.to_s.strip.inspect})", sel.text.include?("4.900–5.600")
  driver.find_element(css: "[data-testid='preview-add-one']").click
  wait.until { rows(driver).size == 2 }
  sleep 1
  check "it becomes a segment", rows(driver).any? { |r| close?(r, [ 4.9, 5.6 ]) }

  puts "==> Adding the whole first layer..."
  driver.find_elements(css: "[data-testid='preview-add-all']")[0].click
  wait.until { rows(driver).size == 4 }
  sleep 1.5
  r = rows(driver).sort
  check "the gaps are filled and overlaps skipped (#{r.inspect})",
        r.size == 4 && [ [ 0.9, 3.1 ], [ 4.9, 5.6 ], HAND_MADE, [ 14.9, 17.1 ] ].all? { |e| r.any? { |x| close?(x, e) } }

  puts "==> Removing the second layer..."
  driver.find_elements(css: "[data-testid='preview-remove']")[1].click
  wait.until { driver.find_elements(css: "[data-testid='preview-layer']").size == 1 }
  check "removed, and kept removed", stored(driver).size == 1

  puts "==> Clearing from Downloaded resources..."
  driver.find_element(css: "[data-testid='resources-open']").click
  wait.until { driver.find_elements(css: "[data-testid='resources-previews']").any?(&:displayed?) }
  listed = driver.find_element(css: "[data-testid='resources-previews']").text
  check "the kit's previews are listed (#{listed.inspect})", listed.include?("(this one): 1 layer, 4 spans")
  driver.find_element(css: "[data-testid^='resources-clear-previews-']").click
  wait.until { driver.find_elements(css: "[data-testid='resources-no-previews']").any? }
  check "cleared, and the lane with them", driver.find_elements(css: "[data-testid='preview-lane']").empty? && stored(driver).empty?
rescue => e
  check "no exception (#{e.class}: #{e.message.lines.first&.strip})", false
end

failed = $results.reject(&:last)
puts ""
puts failed.empty? ? "PASS — #{$results.size} checks" : "FAIL — #{failed.size} of #{$results.size} checks failed"
exit(failed.empty? ? 0 : 1)
