#!/usr/bin/env ruby
# Drives the Downloaded resources dialog (the drive icon in the Controls
# toolbar) in a real browser.
#
# The model store, a kept local-audio handle and a setting are put in place
# first, so there is something to list without downloading a model; the
# recognition Worker is a stand-in that records which model it was asked for
# and reports download progress the way the real one does.
#
#   1. Opening lists the model (grouped, sized, marked in use), the runtime,
#      the handle and the setting, with the site's usage.
#   2. Choosing a size and a language (Tiny, French) gives that model a row;
#      Download: the Worker is asked for it and told the language, progress
#      is shown, then Ready. A language Whisper doesn't know is refused.
#   3. Deleting a model removes its files from the store, and only its files;
#      files nothing claims show as Other files and can be cleared.
#   3b. A WASM module defined from the page — one that doesn't exist yet —
#      is listed, downloads through Cache Storage, and deletes.
#   4. Forgetting handles, resetting a setting, Keep from eviction.
#   5. A reload: the model choice is remembered.
#
#   bin/repl                                         # in another terminal
#   bundle exec ruby script/resources_auto.rb        # HEADLESS=1 for no window
#
# SCREENSHOTS=1 saves the toolbar and the open dialog to Dir.tmpdir.
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

HF = "https://huggingface.co/onnx-community"
BASE = "onnx-community/whisper-base.en"
TINY = "onnx-community/whisper-tiny"   # multilingual: chosen as Tiny, in French
RUNTIME_URL = "https://cdn.jsdelivr.net/npm/onnxruntime-web@1.31.0/dist/ort-wasm-simd-threaded.jsep.wasm"
LEFTOVER_URL = "https://example.org/from-an-older-version.bin"
SEED = {
  "#{HF}/whisper-base.en/resolve/main/onnx/encoder_model_quantized.onnx" => 2_000_000,
  "#{HF}/whisper-base.en/resolve/main/config.json" => 1_000,
  RUNTIME_URL => 500_000,
  LEFTOVER_URL => 3_000
}.freeze
# A WASM module nobody has written yet, defined from the page the way a new
# one would be (resources/index.js). Its "file" is any file the server has.
DEMO_FILE = "/test_tone_10s.wav"

# The dialog re-renders its rows on every refresh, so an element found a
# moment ago can be gone by the time it's used: find it again and retry.
def fresh(tries = 3)
  yield
rescue Selenium::WebDriver::Error::StaleElementReferenceError
  raise if (tries -= 1) <= 0
  sleep 0.2
  retry
end
def row_text(driver, id) = fresh { driver.find_elements(css: "[data-testid='resources-row-#{id}']").first&.text.to_s }
def click_in_row(driver, what, id) = fresh { driver.find_element(css: "[data-testid='resources-#{what}-#{id}']").click }

ctx = TranscriptionReplLib.setup_data
driver = TranscriptionReplLib.launch_browser_signed_in(user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task])
at_exit { driver.quit rescue nil }
driver.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
  window.__models = [];
  window.Worker = class {
    constructor(){ this.onmessage = null; this.onerror = null; }
    postMessage(m){
      if (!m || m.type !== 'run') return;
      window.__models.push(m.model);
      (window.__languages ||= []).push(m.language);
      const say = (d, t) => setTimeout(() => this.onmessage && this.onmessage({ data: d }), t);
      say({ type: 'progress', stage: 'downloading', file: 'encoder', loaded: 40, total: 100 }, 50);
      say({ type: 'progress', stage: 'downloading', file: 'encoder', loaded: 100, total: 100 }, 400);
      say({ type: 'progress', stage: 'transcribing' }, 500);
      say({ type: 'done', text: '', chunks: [] }, 600);
    }
    terminate(){}
  };
JS
driver.execute_script("localStorage.removeItem('asr_size'); localStorage.removeItem('asr_language')")
driver.navigate.refresh
wait = Selenium::WebDriver::Wait.new(timeout: 30)

def dialog_text(driver) = driver.find_element(css: "[data-testid='resources-dialog']").text
def cache_urls(driver, name = "transformers-cache")
  driver.execute_async_script(<<~JS, name)
    const done = arguments[arguments.length - 1];
    caches.open(arguments[0]).then(c => c.keys()).then(k => done(k.map(r => r.url)));
  JS
end
def open_dialog(driver, wait)
  driver.find_element(css: "[data-testid='resources-open']").click
  wait.until { driver.find_elements(css: "[data-testid='resources-dialog']").any?(&:displayed?) }
  sleep 1
end

begin
  wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
  driver.find_elements(css: "[aria-label='Close guide']").find(&:displayed?)&.click

  puts "==> Putting things in the browser to find..."
  err = driver.execute_async_script(<<~JS, SEED)
    const done = arguments[arguments.length - 1];
    (async () => {
      const c = await caches.open('transformers-cache');
      for (const [url, n] of Object.entries(arguments[0]))
        await c.put(url, new Response(new Uint8Array(n), { headers: { 'content-length': String(n) } }));
      const root = await navigator.storage.getDirectory();
      const h = await root.getFileHandle('kept interview.wav', { create: true });
      await new Promise((ok, bad) => {
        const r = indexedDB.open('local-audio', 1);
        r.onupgradeneeded = () => r.result.createObjectStore('handles');
        r.onsuccess = () => { const t = r.result.transaction('handles', 'readwrite'); t.objectStore('handles').put(h, 'kit-123'); t.oncomplete = () => { r.result.close(); ok(); }; t.onerror = () => bad(t.error); };
        r.onerror = () => bad(r.error);
      });
      localStorage.setItem('energy_segments', '{"margin_db":12}');
    })().then(() => done(null), (e) => done(String(e)));
  JS
  raise "seeding failed: #{err}" if err

  driver.execute_script(<<~JS, DEMO_FILE)
    window.ldc_resources.define_wasm_module({ id: 'demo', label: 'Demo module',
      description: 'a stand-in for a module not written yet', files: { wasm: arguments[0] } });
  JS

  puts "==> Opening the dialog..."
  driver.save_screenshot(File.join(Dir.tmpdir, "resources_toolbar.png")) if ENV["SCREENSHOTS"]
  open_dialog(driver, wait)
  driver.save_screenshot(File.join(Dir.tmpdir, "resources_dialog.png")) if ENV["SCREENSHOTS"]
  t = dialog_text(driver)
  usage = driver.find_element(css: "[data-testid='resources-usage']").text
  check "the site's usage is reported (#{usage.inspect})", usage.match?(/uses \S+ \S+ of the \S+ \S+ the browser allows/)
  base_row = row_text(driver, "speech-model:#{BASE}")
  check "the model is listed, its files together, sized and in use (#{base_row.inspect})",
        base_row.include?("2 files · in use") && base_row.include?("1.9 MB")
  rt = row_text(driver, "speech-runtime:runtime")
  check "the runtime is listed apart (#{rt.lines.first.to_s.strip.inspect})", rt.include?("Recognition runtime") && rt.include?("488 KB")
  other = row_text(driver, "other:transformers-cache")
  check "a file nothing claims is listed as Other files (#{other.lines.first.to_s.strip.inspect})", other.include?("Other files") && other.include?("2.9 KB")
  demo = row_text(driver, "demo:demo")
  check "a newly defined module is listed, not yet downloaded (#{demo.lines.first.to_s.strip.inspect})",
        demo.include?("Demo module") && demo.include?("not downloaded")
  check "the kept local-audio file is listed", t.include?("kept interview.wav") && t.include?("kit-123")
  check "the setting is listed with its value", t.include?('{"margin_db":12}')

  puts "==> Choosing Tiny, in French, and downloading it now..."
  driver.find_element(css: "[data-testid='resources-size-tiny']").click
  check "Tiny in English is the English-only model (#{driver.find_element(css: "[data-testid='resources-model-in-use']").text.inspect})",
        driver.find_element(css: "[data-testid='resources-model-in-use']").text.include?("whisper-tiny.en")
  lang = driver.find_element(css: "[data-testid='resources-language']")
  lang.click
  lang.send_keys([ :command, "a" ], :backspace)
  lang.send_keys([ :control, "a" ], :backspace)
  lang.send_keys("Klingon", :enter)
  err = wait.until { driver.find_element(css: "[data-testid='resources-dialog'] [role='alert']") }
  check "a language Whisper doesn't know is refused (#{err.text.inspect})", err.text.include?("doesn't know")
  lang = driver.find_element(css: "[data-testid='resources-language']")
  lang.click
  lang.send_keys([ :command, "a" ], :backspace)
  lang.send_keys([ :control, "a" ], :backspace)
  lang.send_keys("french", :enter)
  wait.until { driver.find_element(css: "[data-testid='resources-model-in-use']").text.include?("told it's hearing French") }
  in_use = driver.find_element(css: "[data-testid='resources-model-in-use']").text
  check "French makes it the multilingual model, told the language (#{in_use.inspect})", in_use.include?(TINY) && !in_use.include?(".en")
  check "both choices are kept for this browser",
        driver.execute_script("return [localStorage.getItem('asr_size'), localStorage.getItem('asr_language')]") == [ "tiny", "fr" ]
  tiny_id = "speech-model:#{TINY}"
  wait.until { row_text(driver, tiny_id).include?("not downloaded · in use") }
  check "the chosen model has a row of its own, ready to download", true
  click_in_row(driver, "download", tiny_id)
  seen = []
  wait.until { seen << driver.find_element(css: "[data-testid='resources-status-#{tiny_id}']").text; seen.last == "Ready." }
  check "progress is shown, then Ready (#{seen.uniq.inspect})", seen.any? { |s| s.match?(/Downloading… \d+%/) }
  check "the Worker was asked for that model, in French (#{driver.execute_script('return [window.__models, window.__languages]').inspect})",
        driver.execute_script("return window.__models") == [ TINY ] && driver.execute_script("return window.__languages") == [ "fr" ]

  puts "==> Deleting base.en..."
  click_in_row(driver, "delete", "speech-model:#{BASE}")
  wait.until { row_text(driver, "speech-model:#{BASE}").empty? }
  urls = cache_urls(driver)
  check "its files are gone from the store, and only its files (#{urls.inspect})", urls.sort == [ LEFTOVER_URL, RUNTIME_URL ].sort
  click_in_row(driver, "delete", "other:transformers-cache")
  wait.until { row_text(driver, "other:transformers-cache").empty? }
  check "Other files can be cleared too", cache_urls(driver) == [ RUNTIME_URL ]

  puts "==> Downloading and deleting the new module..."
  click_in_row(driver, "download", "demo:demo")
  wait.until { driver.find_element(css: "[data-testid='resources-status-demo:demo']").text == "Ready." }
  demo = row_text(driver, "demo:demo")
  kept = cache_urls(driver, "optional-modules")
  check "it downloads through Cache Storage and is listed with its size (#{demo.lines.first.to_s.strip.inspect}, #{kept.inspect})",
        kept.size == 1 && kept[0].end_with?(DEMO_FILE) && demo.include?("1 file") && demo.include?("313 KB")
  click_in_row(driver, "delete", "demo:demo")
  wait.until { row_text(driver, "demo:demo").include?("not downloaded") }
  check "and deleting it empties its cache, leaving the row to download again", cache_urls(driver, "optional-modules").empty?

  puts "==> Forgetting handles, resetting a setting, keep from eviction..."
  driver.find_element(css: "[data-testid='resources-forget-handles']").click
  wait.until { driver.find_elements(css: "[data-testid='resources-no-handles']").any? }
  check "handles forgotten", true
  driver.find_element(css: "[data-testid='resources-reset-energy_segments']").click
  check "the setting is reset", driver.execute_script("return localStorage.getItem('energy_segments')").nil?
  if (b = driver.find_elements(css: "[data-testid='resources-persist']").first)
    b.click
    sleep 1
    t = dialog_text(driver)
    check "keep from eviction gets an answer (#{t[/Kept:[^\n]*|The browser declined[^\n]*/].inspect})", t.match?(/Kept:|The browser declined/)
  else
    check "already kept from eviction", driver.find_elements(css: "[data-testid='resources-persisted']").any?
  end

  puts "==> Reloading..."
  driver.navigate.refresh
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
  open_dialog(driver, wait)
  check "the size and language are remembered",
        driver.find_element(css: "[data-testid='resources-size-tiny']").selected? &&
        driver.find_element(css: "[data-testid='resources-language']").attribute("value") == "French"
rescue => e
  check "no exception (#{e.class}: #{e.message.lines.first&.strip})", false
end

failed = $results.reject(&:last)
puts ""
puts failed.empty? ? "PASS — #{$results.size} checks" : "FAIL — #{failed.size} of #{$results.size} checks failed"
exit(failed.empty? ? 0 : 1)
