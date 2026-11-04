#!/usr/bin/env ruby
# Drives ASR suggestions (the experimental toolbar mode, asr_preview.svelte.js)
# in a real browser, against speech whose words are known: three phrases spoken
# by macOS `say`, placed at known times in one recording.
#
#   1. A segment by hand over each phrase, left empty; no suggestions while
#      the mode is off.
#   2. Mode on at the first segment: the two ahead show suggestions, unsaved;
#      the active one, empty, has its suggestion saved.
#   3. Selecting the second saves its suggestion; clearing that text and
#      coming back doesn't put it back.
#   4. A reload: the mode is remembered, and the saved texts — each one change
#      message — come back from the annotation log.
#
# Needs macOS (for `say`) and network access to the model host on the first
# run: the model (~77 MB) is cached in a Chrome profile kept under tmp/, so
# later runs don't download it again.
#
#   bin/repl                                                      # in another terminal
#   FAKE_ENGINE=1 bundle exec ruby script/segment_asr_auto.rb     # everything but the model
#   bundle exec ruby script/segment_asr_auto.rb                   # the real model
#
# HEADLESS=1 for no window. With FAKE_ENGINE the checks are on what was asked
# (each segment's length in samples) rather than on words; see FAKE below.
# BYPASS_CSP=1 and NO_WEBGPU=1 are for diagnosing a model that won't load.
#
# Known, October 2026: the real model doesn't load under bin/repl — the
# Worker's import of onnxruntime's blob: module fails ("no available backend
# found … Failed to fetch dynamically imported module: blob:…"), on WebGPU and
# WASM alike. The page's script-src has no blob:, which alone blocks it, but
# it still fails with the CSP bypassed, so that isn't the whole story. It is
# the engine, not this feature: whole-file in-browser ASR (Services 5) fails
# the same way.
#
# Exit 0 = PASS, 1 = FAIL.

ENV["RAILS_ENV"] ||= "repl"

require_relative "transcription_repl_lib"
require "fileutils"
require "tmpdir"

abort "needs macOS `say`" unless system("which say > /dev/null")

TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

SR = 16000
PHRASES = [
  { at: 1.0, text: "The quick brown fox jumps over the lazy dog.", expect: /quick|brown|fox|lazy/i },
  { at: 6.0, text: "Please call Stella and ask her to bring these things.", expect: nil },
  { at: 11.0, text: "Transcription in the browser keeps the audio at home.", expect: /transcription|browser|audio|home/i }
].freeze
SECONDS = 16
TYPED = "typed by hand"

# The PCM of a WAV `say` wrote, whatever chunks it put before the data.
def pcm_of(path)
  b = File.binread(path)
  i = 12
  while i < b.bytesize
    id, size = b[i, 8].unpack("a4V")
    return b[i + 8, size] if id == "data"
    i += 8 + size + (size.odd? ? 1 : 0)
  end
  raise "no data chunk in #{path}"
end

dir = Dir.mktmpdir("segment_asr_auto")
at_exit { FileUtils.rm_rf dir }
samples = Array.new(SR * SECONDS, 0)
PHRASES.each_with_index do |p, n|
  f = File.join(dir, "p#{n}.wav")
  system("say", "-o", f, "--file-format=WAVE", "--data-format=LEI16@#{SR}", p[:text], exception: true)
  pcm = pcm_of(f).unpack("s<*")
  p[:end] = p[:at] + pcm.size.to_f / SR
  start = (p[:at] * SR).round
  pcm.each_with_index { |v, k| samples[start + k] = v if start + k < samples.size }
end
data = samples.pack("s<*")
NAME = "segment_asr_speech.wav"
PUBLIC_PATH = Rails.root.join("public", NAME).to_s
File.binwrite(PUBLIC_PATH, [ "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, SR, SR * 2, 2, 16, "data", data.bytesize ]
  .pack("a4Va4a4VvvVVvva4V") + data)
at_exit { FileUtils.rm_f PUBLIC_PATH }

$results = []
def check(label, ok)
  $results << [ label, ok ]
  puts "  #{ok ? 'ok  ' : 'FAIL'} #{label}"
end

ctx = TranscriptionReplLib.setup_data(source_uid: "/#{NAME}", source_filename: NAME,
                                      kit_type_name: "segment_asr_repl", name_suffix: "_segment_asr")

# A profile that outlives the run, so the model is downloaded once.
profile = Rails.root.join("tmp", "segment_asr_chrome_profile").to_s
FileUtils.mkdir_p profile
require "selenium-webdriver"
options = Selenium::WebDriver::Chrome::Options.new
options.add_argument("--window-size=1400,1000")
options.add_argument("--user-data-dir=#{profile}")
if ENV["HEADLESS"]
  options.add_argument("--headless=new")
end
path = TranscriptionReplLib.resolve_managed_chromedriver
driver = path ? Selenium::WebDriver.for(:chrome, options: options, service: Selenium::WebDriver::Service.chrome(path: path))
              : Selenium::WebDriver.for(:chrome, options: options)
at_exit { driver.quit rescue nil }
# BYPASS_CSP=1 ignores the page's Content-Security-Policy, to tell a policy
# refusal from anything else when the model fails to load.
driver.execute_cdp("Page.setBypassCSP", enabled: true) if ENV["BYPASS_CSP"]
# FAKE_ENGINE=1 replaces the page's Worker with a stand-in that answers each
# request at once with "heard N samples" — everything but the model, without
# the model: the key, the session, each segment's audio read and decoded, the
# writes, the batch, the reload. The real-model run checks words instead.
FAKE = !!ENV["FAKE_ENGINE"]
if FAKE
  driver.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
    window.__asr_requests = [];
    window.__asr_timestamps = [];
    window.__workers = 0;
    window.Worker = class {
      constructor(){ this.onmessage = null; this.onerror = null; window.__workers++; }
      postMessage(m){
        if (!m || m.type !== 'run') return;
        window.__asr_requests.push(m.samples.length);
        (window.__single_pass ||= []).push(!!m.single_pass);
        window.__asr_timestamps.push(m.timestamps);
        const say = (d, t) => setTimeout(() => this.onmessage && this.onmessage({ data: d }), t);
        if (m.timestamps === false) {
          // A segment at a time: text, at once.
          say({ type: 'done', text: `heard ${m.samples.length} samples`, chunks: [] }, 50);
          return;
        }
        // A whole-file run, as the real Worker reports one: the model's
        // files downloading at their real sizes, then each 30 s window.
        say({ type: 'progress', stage: 'downloading', file: 'encoder', loaded: 11000000, total: 23201320 }, 50);
        say({ type: 'progress', stage: 'downloading', file: 'decoder', loaded: 52000000, total: 52000000 }, 300);
        say({ type: 'progress', stage: 'downloading', file: 'encoder', loaded: 23201320, total: 23201320 }, 600);
        say({ type: 'progress', stage: 'ready' }, 800);
        [0, 1, 2].forEach((done) => say({ type: 'progress', stage: 'transcribing', device: 'wasm', done, total: 2 }, 1100 + 700 * done));
        say({ type: 'done', device: 'wasm', text: 'whole file', chunks: [ { timestamp: [ 4.2, 5.2 ], text: 'whole file' } ],
              timing: { windows: [ 700, 700 ], passes: 4, merge: 300 } }, 2800);
      }
      terminate(){}
    };
  JS
end
# NO_WEBGPU=1 hides WebGPU from the page, so the Worker runs on WASM.
if ENV["NO_WEBGPU"]
  driver.execute_cdp("Page.addScriptToEvaluateOnNewDocument",
                     source: "Object.defineProperty(Navigator.prototype, 'gpu', { get: () => undefined, configurable: true });")
end
driver.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
  window.__errs = [];
  const ce = console.error.bind(console);
  console.error = (...a) => { window.__errs.push(a.map(String).join(' ')); ce(...a); };
  addEventListener('unhandledrejection', (e) => window.__errs.push('rejection: ' + (e.reason && (e.reason.stack || e.reason.message) || e.reason)));
  // Toasts come and go; keep what each said.
  window.__toasts = [];
  addEventListener('DOMContentLoaded', () => new MutationObserver(() => {
    for (const t of document.querySelectorAll('[data-sonner-toast]')) {
      const x = t.innerText.trim();
      if (x && window.__toasts[window.__toasts.length - 1] !== x) window.__toasts.push(x);
    }
  }).observe(document.body, { subtree: true, childList: true, characterData: true }));
JS
host = TranscriptionReplLib::HOST
driver.navigate.to "#{host}/session/new"
if driver.find_elements(name: "email_address").any?
  driver.find_element(name: "email_address").send_keys(ctx[:user].email_address)
  driver.find_element(name: "password").send_keys(TranscriptionReplLib::PASSWORD)
  driver.find_element(name: "commit").click
  sleep 1
end
# The profile is kept between runs, and so is the mode's last setting.
driver.execute_script("localStorage.setItem('asr_preview', 'off'); localStorage.removeItem('asr_single_pass')")
driver.navigate.to "#{host}/workflows/#{ctx[:task_user].id}/work/#{ctx[:task].workflow_id}"

wait = Selenium::WebDriver::Wait.new(timeout: 30)
slow = Selenium::WebDriver::Wait.new(timeout: Integer(ENV["SLOW"] || 600), interval: 1)   # a model download

# Each row's saved text, and the suggestion shown in it if any.
def rows(driver)
  driver.execute_script(<<~JS)
    return [...document.querySelectorAll('#segments .segment')].map(s => {
      const m = s.textContent.match(/(\\d+\\.\\d{3})\\s+(\\d+\\.\\d{3})/);
      const t = s.querySelector('textarea');
      const sug = s.querySelector('[data-testid="asr-suggestion"]');
      const plain = s.querySelector('.transcript');
      return {
        beg: m && parseFloat(m[1]),
        active: !!t,
        text: t ? t.value : (sug ? '' : (plain ? plain.innerText.trim() : '')),
        suggestion: sug ? sug.innerText.trim() : null
      };
    });
  JS
end
def row_at(driver, n) = rows(driver).find { |r| r["beg"] && (r["beg"] - (PHRASES[n][:at] - 0.2)).abs < 0.05 } || {}
def text_of(driver, n) = row_at(driver, n)["text"].to_s
def click_row(driver, n)
  i = rows(driver).index { |r| r["beg"] && (r["beg"] - (PHRASES[n][:at] - 0.2)).abs < 0.05 }
  driver.find_elements(css: "#segments .segment")[i].click
  sleep 0.4
end

# What a phrase's segment should come back as: with the real model, words;
# with the fake one, the segment's own length in samples (±10 ms).
def heard_right?(n, text)
  return text.match?(PHRASES[n][:expect] || /\w/) unless FAKE
  want = ((PHRASES[n][:end] - PHRASES[n][:at] + 0.4) * SR).round
  (text[/\d+/].to_i - want).abs <= 160
end

# Services 5 asks over which stretch, and whether to preview or add: the whole
# recording (fields emptied the way a person would), then the button.
def answer_stretch(driver, wait, button, from: nil, to: nil)
  d = wait.until { driver.find_elements(css: "dialog[open]").find { |x| x.text.include?("In-browser ASR over which stretch?") } }
  d.find_elements(css: "input").zip([ from, to ]).each do |f, v|
    f.click
    f.send_keys([ :command, "a" ], :backspace)
    f.send_keys([ :control, "a" ], :backspace)
    f.send_keys(v.to_s) if v
  end
  d.find_element(css: "[data-testid='#{button}']").click
end

kit_changes = lambda do
  kit = Kit.where(task: ctx[:task]).order(:id).last
  Annotation.where(tree_id: kit.tree_id, message: "change")
end

begin
  wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
  sleep 0.5
  driver.find_elements(css: "[aria-label='Close guide']").find(&:displayed?)&.click

  puts "==> A segment over each phrase..."
  PHRASES.each do |p|
    driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", p[:at] - 0.2, p[:end] - p[:at] + 0.4)
    sleep 0.2
    prior = driver.find_elements(css: "#segments .segment").size
    keyboard = driver.find_element(css: ".keyboard")
    keyboard.click
    keyboard.send_keys(:enter)
    # Until the new row exists and is the active one, the textarea on screen
    # is the previous row's (as transcription_auto.rb waits).
    wait.until { driver.find_elements(css: "#segments .segment").size == prior + 1 }
    wait.until { row_at(driver, PHRASES.index(p))["active"] }
    sleep 0.6
  end
  check "three empty segments, and no suggestions while the mode is off",
        rows(driver).size == 3 && rows(driver).all? { |r| r["text"].empty? && r["suggestion"].nil? }

  puts "==> Turning on ASR suggestions, at the first segment..."
  click_row(driver, 0)
  driver.find_element(css: "[data-testid='asr-preview-toggle']").click
  # The first is active: its suggestion is saved as soon as it's ready. The
  # two ahead of it only show theirs.
  slow.until { !text_of(driver, 0).empty? && (1..2).all? { |n| row_at(driver, n)["suggestion"].to_s.match?(/\w/) } }
  sleep 1
  saved0 = text_of(driver, 0)
  sug1 = row_at(driver, 1)["suggestion"]
  sug2 = row_at(driver, 2)["suggestion"]
  check "the active empty segment's suggestion is saved (#{saved0.inspect})", heard_right?(0, saved0)
  check "the segments ahead show suggestions (#{sug1.inspect}, #{sug2.inspect})", heard_right?(1, sug1) && heard_right?(2, sug2)
  check "suggestions not selected aren't in the log", kit_changes.call.where(value: [ sug1, sug2 ]).count == 0

  puts "==> Selecting the second..."
  click_row(driver, 1)
  wait.until { text_of(driver, 1) == sug1 }
  sleep 1
  check "selecting an empty segment saves its suggestion", kit_changes.call.where(value: sug1).count == 1

  puts "==> Clearing it, and coming back..."
  ta = driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment")
  ta.send_keys([ :command, "a" ], :backspace)
  ta.send_keys([ :control, "a" ], :backspace)
  ta.send_keys(:tab)
  sleep 1.5
  click_row(driver, 2)
  wait.until { text_of(driver, 2) == sug2 }
  click_row(driver, 1)
  sleep 1.5
  check "text the annotator deleted isn't put back (#{text_of(driver, 1).inspect})", text_of(driver, 1).empty?

  if FAKE
    workers = driver.execute_script("return window.__workers")
    check "one Worker throughout (#{workers})", workers == 1
    ts = driver.execute_script("return window.__asr_timestamps")
    check "suggestions are asked for without timestamps", ts.all? { |t| t == false }
    reqs = driver.execute_script("return window.__asr_requests")
    check "each segment asked about once (#{reqs.inspect})", reqs.size == 3
  end

  puts "==> Reloading..."
  driver.navigate.refresh
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
  wait.until { driver.find_elements(css: "#segments .segment").size == 3 }
  sleep 1
  check "the mode is remembered", driver.find_element(css: "[data-testid='asr-preview-toggle']").attribute("aria-pressed") == "true"
  check "the saved texts come back from the log, the cleared one empty",
        text_of(driver, 0) == saved0 && text_of(driver, 2) == sug2 && text_of(driver, 1).empty?
  counts = [ saved0, sug1, sug2 ].to_h { |t| [ t, kit_changes.call.where(value: t).count ] }
  check "each saved text is one change message in the log (#{counts.inspect})", counts.values.all? { |c| c == 1 }

  if FAKE
    puts "==> Services 5 as a preview..."
    before = driver.find_elements(css: "#segments .segment").size
    driver.execute_script("[...document.querySelectorAll('dialog')].find(x => x.textContent.includes('Available Services')).showModal();")
    sleep 0.3
    driver.execute_script(<<~JS)
      const d = [...document.querySelectorAll('dialog[open]')].find(x => x.textContent.includes('Available Services'));
      d.querySelector('[tabindex="0"]').dispatchEvent(new KeyboardEvent('keydown', { key: '5', bubbles: true, cancelable: true }));
    JS
    # A stretch: only it should be transcribed, and its spans timed from the
    # start of the recording.
    answer_stretch(driver, wait, 'span-preview', from: 0.5, to: 10)
    toast = wait.until { driver.find_elements(css: "[data-sonner-toast]").find { |t| t.text.include?("Preview:") && t.text.include?("in-browser ASR") } }
    check "a preview, not segments (#{toast.text.inspect})", toast.text.include?("1 span from in-browser ASR") && toast.text.include?("Nothing was added")
    sent_len = driver.execute_script("return window.__asr_requests").last
    check "only the stretch was transcribed: 9.5 s of samples (#{sent_len})", (sent_len - 9.5 * SR).abs <= 16
    check "and nothing was left out as outside it", !toast.text.include?("outside the stretch")
    layer = wait.until { driver.find_elements(css: "[data-testid='preview-layer']").find { |l| l.text.include?("In-browser ASR") } }
    check "a layer named by the run and its model (#{layer.text.lines.first.to_s.strip.inspect})", layer.text.include?("In-browser ASR (whisper-base.en)")
    kept = driver.execute_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      const r = indexedDB.open('span_layers', 1);
      r.onupgradeneeded = () => r.result.createObjectStore('layers');
      r.onsuccess = () => {
        const q = r.result.transaction('layers').objectStore('layers').get(window.ldc.obj2._id);
        q.onsuccess = () => { r.result.close(); done((q.result || []).filter(l => l.source === 'local').map(l => l.segments)); };
      };
    JS
    check "its span carries the recognised text, timed from the recording's start (#{kept.inspect})",
          kept.last == [ { "beg" => 4.7, "end" => 5.7, "docid" => kept.last&.first&.dig("docid"), "text" => "whole file" } ]
    check "and the transcript is unchanged", driver.find_elements(css: "#segments .segment").size == before
    layer.find_element(css: "[data-testid='preview-add-all']").click
    wait.until { driver.find_elements(css: "#segments .segment").size == before + 1 }
    added = rows(driver).find { |r| r["text"] == "whole file" }
    check "adding it from the lane makes the segment, text and all", !added.nil?

    puts "==> Services 5, a whole-file run..."
    before = driver.find_elements(css: "#segments .segment").size
    # Every label the progress panel shows during the run.
    driver.execute_script(<<~JS)
      window.__panel = [];
      new MutationObserver(() => {
        const p = document.querySelector('[data-testid="bulk-panel"]');
        const t = p && p.innerText.replace(/\s+/g, ' ').trim();
        if (t && window.__panel[window.__panel.length - 1] !== t) window.__panel.push(t);
      }).observe(document.body, { subtree: true, childList: true, characterData: true });
    JS
    driver.execute_script("[...document.querySelectorAll('dialog')].find(x => x.textContent.includes('Available Services')).showModal();")
    sleep 0.3
    driver.execute_script(<<~JS)
      const d = [...document.querySelectorAll('dialog[open]')].find(x => x.textContent.includes('Available Services'));
      d.querySelector('[tabindex="0"]').dispatchEvent(new KeyboardEvent('keydown', { key: '5', bubbles: true, cancelable: true }));
    JS
    answer_stretch(driver, wait, 'span-run')
    toast = wait.until { driver.find_elements(css: "[data-sonner-toast]").find { |t| t.text.include?("added from in-browser ASR") } }
    check "it ends with a summary toast (#{toast.text.inspect})", toast.text.include?("1 segment added")
    check "saying how long the model took to be ready, transcribing took, and on which backend",
          toast.text.match?(/model ready in [\d.]+ s; transcribing took [\d.]+ s on WASM/)
    check "and each window, the joining and the adding",
          toast.text.match?(/on WASM: windows 0\.7, 0\.7 s \(4 passes\), joining 0\.3 s; adding took [\d.]+ s\)/)
    labels = driver.execute_script("return window.__panel || []")
    check "the panel showed the download as one percentage, then the parts (#{labels.inspect})",
          labels.any? { |l| l.match?(/Downloading the speech model \(\d+%\)/) } &&
          labels.any? { |l| l.include?("Transcribing in this browser (part 1 of 2)") } &&
          labels.any? { |l| l.include?("(part 2 of 2)") } &&
          labels.any? { |l| l.include?("(putting the parts together)") }
    check "and never a byte count", labels.none? { |l| l.match?(/\d{4,}/) }
    check "and no dialog over the page", driver.find_elements(css: "dialog[open]").none? { |d| d.text.include?("Automatic Speech Recognition") }
    wait.until { driver.find_elements(css: "#segments .segment").size == before + 1 }
    check "its segment is in the transcript", true


    puts "==> Again, with one pass per window..."
    driver.find_element(css: "[data-testid='resources-open']").click
    box = wait.until { driver.find_element(css: "[data-testid='resources-single-pass']") }
    box.click
    check "the setting is kept for this browser", driver.execute_script("return localStorage.getItem('asr_single_pass')") == "on"
    driver.action.send_keys(:escape).perform
    sleep 0.3
    driver.execute_script("[...document.querySelectorAll('dialog')].find(x => x.textContent.includes('Available Services')).showModal();")
    sleep 0.3
    driver.execute_script(<<~JS)
      const d = [...document.querySelectorAll('dialog[open]')].find(x => x.textContent.includes('Available Services'));
      d.querySelector('[tabindex="0"]').dispatchEvent(new KeyboardEvent('keydown', { key: '5', bubbles: true, cancelable: true }));
    JS
    answer_stretch(driver, wait, 'span-run')
    toast = wait.until { driver.find_elements(css: "[data-sonner-toast]").find { |t| t.text.include?("one pass per window") } }
    check "the run says it went one pass per window (#{toast.text.inspect})", toast.text.include?("on WASM, one pass per window: windows")
    sent = driver.execute_script("return window.__single_pass")
    check "and the Worker was told so, this run only (#{sent.last(2).inspect})", sent.last(2) == [ false, true ]
    driver.execute_script("localStorage.removeItem('asr_single_pass')")
  end
rescue => e
  check "no exception (#{e.class}: #{e.message.lines.first&.strip})", false
  errs = (driver.execute_script("return window.__errs || []") rescue [])
  puts "  page errors:", errs.last(10).map { |x| "    #{x[0, 400]}" } if errs.any?
  puts "  rows: #{(rows(driver) rescue []).inspect}"
  toasts = (driver.execute_script("return window.__toasts") rescue [])
  puts "  toasts: #{Array(toasts).last(4).inspect}"
end

failed = $results.reject(&:last)
puts ""
puts failed.empty? ? "PASS — #{$results.size} checks" : "FAIL — #{failed.size} of #{$results.size} checks failed"
exit(failed.empty? ? 0 : 1)
