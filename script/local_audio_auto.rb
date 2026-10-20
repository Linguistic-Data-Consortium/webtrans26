#!/usr/bin/env ruby
# Drives the local_audio kit type end to end in a real browser, twice:
#
#   handles   the browser can keep a handle to the file (Chrome, Edge). The
#             native file dialog can't be driven, so showOpenFilePicker is
#             stubbed to return a real handle into the origin-private file
#             system, written with the test tone first. Such a handle reads
#             like any other and can be kept in IndexedDB.
#   fallback  showOpenFilePicker removed, as in Safari and Firefox: a plain
#             <input type=file>, and the file is asked for on every visit.
#
# Each run checks:
#
#   1. An OnTheFly task whose kit type carries local_audio. The work page shows
#      a file picker and makes no kit.
#   2. Picking a WAV makes and assigns the kit, named local://<file name>, and
#      the waveform renders from the file — no request for the audio.
#   3. A segment is made and typed, and lands in the annotation log as usual.
#   4. The Services dialog offers nothing, and its keys start nothing.
#   5. Coming back: with handles, the kit reopens with no picker, or with one
#      click when permission has lapsed, and a file that has gone is reported
#      and can be chosen again. Without, the file is asked for again, and the
#      wrong one is refused.
#
#   bin/repl                                         # in another terminal
#   bundle exec ruby script/local_audio_auto.rb      # HEADLESS=1 for no window
#
# Exit 0 = PASS, 1 = FAIL.

ENV["RAILS_ENV"] ||= "repl"

require_relative "transcription_repl_lib"
require "fileutils"
require "base64"

TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

FILE_NAME = "local interview.wav"
OTHER_NAME = "some other.wav"
SEGMENT_TEXT = "from my own disk"
dir = Dir.mktmpdir("local_audio_auto")
at_exit { FileUtils.rm_rf dir }
tone = Rails.root.join("public/test_tone_10s.wav").to_s
LOCAL_PATH = File.join(dir, FILE_NAME)
OTHER_PATH = File.join(dir, OTHER_NAME)
FileUtils.cp tone, LOCAL_PATH
FileUtils.cp tone, OTHER_PATH
TONE_B64 = Base64.strict_encode64(File.binread(tone))

# Installed before any page script runs, on every load.
#
#   handles   showOpenFilePicker returns the OPFS file named by
#             localStorage.__pick. localStorage.__lapse makes every handle
#             report its permission as lapsed, and grants it on request — the
#             state a real handle is in after a reload until the user allows it.
#   fallback  no showOpenFilePicker at all.
STUB = {
  handles: <<~JS,
    window.showOpenFilePicker = async () => {
      const root = await navigator.storage.getDirectory();
      return [ await root.getFileHandle(localStorage.getItem('__pick') || #{FILE_NAME.to_json}) ];
    };
    if (localStorage.getItem('__lapse')) {
      FileSystemFileHandle.prototype.queryPermission = async () => 'prompt';
      FileSystemFileHandle.prototype.requestPermission = async () => {
        window.__asked = true;
        return 'granted';
      };
    }
  JS
  fallback: <<~JS
    try { delete Window.prototype.showOpenFilePicker; } catch (e) {}
    window.showOpenFilePicker = undefined;
  JS
}.freeze

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

def picker?(driver)
  driver.find_elements(css: "[data-testid^='local-audio-']").any?
end

def segment_text(driver, wait)
  wait.until { driver.find_elements(css: "#segments .segment").any? }
  driver.execute_script(<<~JS)
    return [...document.querySelectorAll('#segments .segment')].map(s => {
      const t = s.querySelector('textarea');
      return t ? t.value : s.textContent;
    }).join(' | ');
  JS
end

def opfs(driver, script)
  driver.execute_async_script(<<~JS)
    const done = arguments[arguments.length - 1];
    (async () => { const root = await navigator.storage.getDirectory(); #{script} })()
      .then(() => done(null), (e) => done(String(e)));
  JS
end

def write_opfs(driver, name)
  err = opfs(driver, <<~JS)
    const bytes = Uint8Array.from(atob(#{TONE_B64.to_json}), c => c.charCodeAt(0));
    const w = await (await root.getFileHandle(#{name.to_json}, { create: true })).createWritable();
    await w.write(bytes); await w.close();
  JS
  raise "OPFS write failed: #{err}" if err
end

def run(mode)
  puts ""
  puts "=================== #{mode} ==================="
  ctx = TranscriptionReplLib.setup_data(
    kit_type_name: "local_audio_repl", name_suffix: "_local_audio",
    extra_constraints: { "local_audio" => "local_audio" }
  )
  task = ctx[:task]
  task.update!(workflow: Workflow.find_by!(name: "OnTheFly"))
  # setup_data seeds an unassigned kit for the Orderly path; OnTheFly makes
  # its own, and that one should be the only kit here.
  Kit.where(task: task).destroy_all
  ctx[:task_user].update!(state: "needs_kit", kit_oid: nil)

  driver = TranscriptionReplLib.launch_browser_signed_in(user: ctx[:user], task_user: ctx[:task_user], task: task.reload)
  wait = Selenium::WebDriver::Wait.new(timeout: 30)
  driver.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: STUB.fetch(mode))
  driver.execute_script("localStorage.removeItem('__pick'); localStorage.removeItem('__lapse');")
  if mode == :handles
    write_opfs(driver, FILE_NAME)
    write_opfs(driver, OTHER_NAME)
  end
  driver.navigate.refresh

  choose = mode == :handles ? "[data-testid='local-audio-choose']" : "[data-testid='local-audio-input']"
  control = wait.until { driver.find_element(css: choose) }
  check "the work page asks for a file", true
  check "and makes no kit before one is picked", Kit.where(task: task).count == 0

  if mode == :handles
    control.click
  else
    control.send_keys(LOCAL_PATH)
  end
  wait_for_tool(driver, wait)

  kit = Kit.where(task: task).sole
  check "picking it makes one kit, named local://<file name>", kit.source_uid == "local://#{FILE_NAME}"
  check "with the file's size recorded", kit.source[:size] == File.size(LOCAL_PATH)
  check "assigned to the annotator", kit.state == "assigned" && kit.user_id == ctx[:user].id
  check "the picker is gone", !picker?(driver)

  audio_requests = driver.execute_script(<<~JS)
    return performance.getEntriesByType('resource').map(e => e.name)
      .filter(n => /\\.wav|test_tone|local%20interview|amazonaws/.test(n));
  JS
  check "the waveform drew without requesting any audio (#{audio_requests.inspect})", audio_requests.empty?

  driver.find_elements(css: "[aria-label='Close guide']").find(&:displayed?)&.click

  puts "==> Making a segment..."
  keyboard = driver.find_element(css: ".keyboard")
  driver.execute_script("window.ldc.wc.set_current_selection(1.0, 1.5)")
  sleep 0.2
  keyboard.click
  keyboard.send_keys(:enter)
  textarea = wait.until { driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment") }
  textarea.send_keys(SEGMENT_TEXT)
  textarea.send_keys(:tab)
  sleep 1.5
  kit.reload
  check "the segment's text is in the annotation log",
        Annotation.where(tree_id: kit.tree_id, message: "change").pluck(:value).include?(SEGMENT_TEXT)

  puts "==> Services..."
  driver.execute_script(<<~JS)
    window.__posts = [];
    const f = window.fetch.bind(window);
    window.fetch = (url, init) => { window.__posts.push(String(url)); return f(url, init); };
    [...document.querySelectorAll('dialog')].find(x => x.textContent.includes('Available Services')).showModal();
  JS
  sleep 0.3
  dialog_text = driver.execute_script("return [...document.querySelectorAll('dialog[open]')].map(d => d.textContent).join(' ')")
  check "the Services dialog says none are available for local audio",
        dialog_text.include?("audio is a file on your computer") && !dialog_text.include?("Speech Activity Detection")
  driver.execute_script(<<~JS)
    const d = [...document.querySelectorAll('dialog[open]')].find(x => x.textContent.includes('Available Services'));
    d.querySelector('[tabindex="0"]').dispatchEvent(new KeyboardEvent('keydown', { key: '1', bubbles: true, cancelable: true }));
  JS
  sleep 1
  posts = driver.execute_script("return window.__posts")
  check "pressing 1 (SAD) sends nothing (#{posts.inspect})", posts.none? { |u| u !~ %r{\A/} || u =~ /hlt|sad|promise/ }

  if mode == :handles
    puts "==> Reloading, permission still held..."
    driver.navigate.refresh
    wait_for_tool(driver, wait)
    check "the kit reopens with no picker", !picker?(driver)
    check "with its segment, from the server (#{segment_text(driver, wait).inspect})", segment_text(driver, wait).include?(SEGMENT_TEXT)

    puts "==> Reloading, permission lapsed..."
    driver.execute_script("localStorage.setItem('__lapse', '1')")
    driver.navigate.refresh
    reopen = wait.until { driver.find_element(css: "[data-testid='local-audio-reopen']") }
    check "it offers to open the same file by name (#{reopen.text.inspect})", reopen.text.include?(FILE_NAME)
    reopen.click
    wait_for_tool(driver, wait)
    check "one click asks the browser and carries on", driver.execute_script("return window.__asked === true")
    check "with its segment (#{segment_text(driver, wait).inspect})", segment_text(driver, wait).include?(SEGMENT_TEXT)
    driver.execute_script("localStorage.removeItem('__lapse')")

    puts "==> Reloading, file gone..."
    err = opfs(driver, "await root.removeEntry(#{FILE_NAME.to_json});")
    raise "OPFS remove failed: #{err}" if err
    driver.navigate.refresh
    alert = wait.until { driver.find_element(css: "[role='alert']") }
    check "a file that has gone is reported (#{alert.text.inspect})", alert.text.include?("moved or deleted")
    check "and no reopen button is offered", driver.find_elements(css: "[data-testid='local-audio-reopen']").empty?

    driver.execute_script("localStorage.setItem('__pick', #{OTHER_NAME.to_json})")
    driver.find_element(css: "[data-testid='local-audio-choose']").click
    alert = wait.until { driver.find_element(css: "[role='alert']") }
    wait.until { driver.find_element(css: "[role='alert']").text.include?(OTHER_NAME) }
    alert = driver.find_element(css: "[role='alert']")
    check "choosing the wrong file is refused (#{alert.text.inspect})", alert.text.include?("not #{OTHER_NAME}")

    write_opfs(driver, FILE_NAME)
    driver.execute_script("localStorage.removeItem('__pick')")
    driver.find_element(css: "[data-testid='local-audio-choose']").click
    wait_for_tool(driver, wait)
    check "choosing it again brings the kit back (#{segment_text(driver, wait).inspect})", segment_text(driver, wait).include?(SEGMENT_TEXT)

    driver.navigate.refresh
    wait_for_tool(driver, wait)
    check "and the new handle is kept: the next reload needs no picker", !picker?(driver)
  else
    puts "==> Reloading..."
    driver.navigate.refresh
    input = wait.until { driver.find_element(css: "[data-testid='local-audio-input']") }
    check "a reload asks for the kit's file again, by name", driver.find_element(tag_name: "body").text.include?(FILE_NAME)

    input.send_keys(OTHER_PATH)
    alert = wait.until { driver.find_element(css: "[role='alert']") }
    check "the wrong file is refused (#{alert.text.inspect})", alert.text.include?("not #{OTHER_NAME}")

    driver.find_element(css: "[data-testid='local-audio-input']").send_keys(LOCAL_PATH)
    wait_for_tool(driver, wait)
    check "the right file brings the kit back (#{segment_text(driver, wait).inspect})", segment_text(driver, wait).include?(SEGMENT_TEXT)
  end
  check "still one kit", Kit.where(task: task).count == 1
rescue => e
  check "no exception (#{e.class}: #{e.message.lines.first&.strip})", false
ensure
  driver&.quit rescue nil
end

modes = ENV["MODE"] ? [ ENV["MODE"].to_sym ] : [ :handles, :fallback ]
modes.each { |m| run(m) }

failed = $results.reject(&:last)
puts ""
puts failed.empty? ? "PASS — #{$results.size} checks" : "FAIL — #{failed.size} of #{$results.size} checks failed"
exit(failed.empty? ? 0 : 1)
