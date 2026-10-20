#!/usr/bin/env ruby
# Drives the local_audio kit type end to end in a real browser:
#
#   1. An OnTheFly task whose kit type carries local_audio. The work page shows
#      a file picker and makes no kit.
#   2. Picking a WAV makes and assigns the kit, named local://<file name>, and
#      the waveform renders from the file on disk — no request for the audio.
#   3. A segment is made and typed, and lands in the annotation log as usual.
#   4. The Services dialog offers nothing, and its keys start nothing.
#   5. Reloading asks for the file again: the wrong one is refused, the right
#      one brings the kit back with its segment, read from the server.
#
#   bin/repl                                         # in another terminal
#   bundle exec ruby script/local_audio_auto.rb      # HEADLESS=1 for no window
#
# Exit 0 = PASS, 1 = FAIL.

ENV["RAILS_ENV"] ||= "repl"

require_relative "transcription_repl_lib"
require "fileutils"

TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

FILE_NAME = "local interview.wav"
dir = Dir.mktmpdir("local_audio_auto")
at_exit { FileUtils.rm_rf dir }
tone = Rails.root.join("public/test_tone_10s.wav").to_s
local_path = File.join(dir, FILE_NAME)
FileUtils.cp tone, local_path
other_path = File.join(dir, "some other.wav")
FileUtils.cp tone, other_path

puts "==> Setting up data..."
ctx = TranscriptionReplLib.setup_data(
  kit_type_name: "local_audio_repl", name_suffix: "_local_audio",
  extra_constraints: { "local_audio" => "local_audio" }
)
task = ctx[:task]
otf = Workflow.find_by!(name: "OnTheFly")
task.update!(workflow: otf)
# setup_data seeds an unassigned kit for the Orderly path; OnTheFly makes its
# own, and that one should be the only kit here.
Kit.where(task: task).destroy_all
ctx[:task_user].update!(state: "needs_kit", kit_oid: nil)

results = []
check = ->(label, ok) { results << [ label, ok ]; puts "  #{ok ? 'ok  ' : 'FAIL'} #{label}" }

puts "==> Launching Chrome..."
driver = TranscriptionReplLib.launch_browser_signed_in(user: ctx[:user], task_user: ctx[:task_user], task: task.reload)
at_exit { driver.quit rescue nil }
wait = Selenium::WebDriver::Wait.new(timeout: 30)

begin
  input = wait.until { driver.find_element(css: "[data-testid='local-audio-input']") }
  check.("the work page asks for a file", true)
  check.("and makes no kit before one is picked", Kit.where(task: task).count == 0)

  input.send_keys(local_path)
  wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc)") }
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
  sleep 0.5

  kit = Kit.where(task: task).sole
  check.("picking it makes one kit, named local://<file name>", kit.source_uid == "local://#{FILE_NAME}")
  check.("with the file's size recorded", kit.source[:size] == File.size(local_path))
  check.("assigned to the annotator", kit.state == "assigned" && kit.user_id == ctx[:user].id)
  check.("the picker is gone", driver.find_elements(css: "[data-testid='local-audio-input']").empty?)

  audio_requests = driver.execute_script(<<~JS)
    return performance.getEntriesByType('resource').map(e => e.name)
      .filter(n => /\\.wav|test_tone|local%20interview|amazonaws/.test(n));
  JS
  check.("the waveform drew without requesting any audio (#{audio_requests.inspect})", audio_requests.empty?)

  guide_close = driver.find_elements(css: "[aria-label='Close guide']").find(&:displayed?)
  guide_close&.click

  puts "==> Making a segment..."
  keyboard = driver.find_element(css: ".keyboard")
  driver.execute_script("window.ldc.wc.set_current_selection(1.0, 1.5)")
  sleep 0.2
  keyboard.click
  keyboard.send_keys(:enter)
  wait.until { driver.find_elements(css: "#segments .segment.active-segment textarea.ann-segment").any? }
  textarea = driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment")
  textarea.send_keys("from my own disk")
  textarea.send_keys(:tab)
  sleep 1.5

  kit.reload
  texts = Annotation.where(tree_id: kit.tree_id, message: "change").pluck(:value)
  check.("the segment's text is in the annotation log", texts.include?("from my own disk"))

  puts "==> Services..."
  # Open the Services dialog directly and press 1 (SAD) in it, watching for any
  # request leaving the page.
  driver.execute_script(<<~JS)
    window.__posts = [];
    const f = window.fetch.bind(window);
    window.fetch = (url, init) => { window.__posts.push(String(url)); return f(url, init); };
    const d = [...document.querySelectorAll('dialog')].find(x => x.textContent.includes('Available Services'));
    d.showModal();
  JS
  sleep 0.3
  dialog_text = driver.execute_script("return [...document.querySelectorAll('dialog[open]')].map(d => d.textContent).join(' ')")
  check.("the Services dialog says none are available for local audio",
         dialog_text.include?("audio is a file on your computer") && !dialog_text.include?("Speech Activity Detection"))
  driver.execute_script(<<~JS)
    const d = [...document.querySelectorAll('dialog[open]')].find(x => x.textContent.includes('Available Services'));
    d.querySelector('[tabindex="0"]').dispatchEvent(new KeyboardEvent('keydown', { key: '1', bubbles: true, cancelable: true }));
  JS
  sleep 1
  posts = driver.execute_script("return window.__posts")
  check.("pressing 1 (SAD) sends nothing (#{posts.inspect})", posts.none? { |u| u !~ %r{\A/} || u =~ /hlt|sad|promise/ })

  puts "==> Reloading..."
  driver.navigate.refresh
  input = wait.until { driver.find_element(css: "[data-testid='local-audio-input']") }
  page = driver.find_element(tag_name: "body").text
  check.("a reload asks for the kit's file again, by name", page.include?(FILE_NAME))
  check.("and makes no second kit", Kit.where(task: task).count == 1)

  input.send_keys(other_path)
  alert = wait.until { driver.find_element(css: "[role='alert']") }
  check.("the wrong file is refused (#{alert.text.inspect})", alert.text.include?("not some other.wav"))

  input = driver.find_element(css: "[data-testid='local-audio-input']")
  input.send_keys(local_path)
  wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
  wait.until { driver.find_elements(css: "#segments .segment").any? }
  seg_text = driver.execute_script(<<~JS)
    return [...document.querySelectorAll('#segments .segment')].map(s => {
      const t = s.querySelector('textarea');
      return t ? t.value : s.textContent;
    }).join(' | ');
  JS
  check.("the right file brings the kit back with its segment (#{seg_text.inspect})", seg_text.include?("from my own disk"))
  check.("still one kit", Kit.where(task: task).count == 1)
rescue => e
  check.("no exception (#{e.class}: #{e.message.lines.first&.strip})", false)
end

failed = results.reject(&:last)
puts ""
puts failed.empty? ? "PASS — #{results.size} checks" : "FAIL — #{failed.size} of #{results.size} checks failed"
exit(failed.empty? ? 0 : 1)
