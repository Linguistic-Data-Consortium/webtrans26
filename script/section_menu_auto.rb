#!/usr/bin/env ruby
# The letters the section menu hands out, driven end to end.
#
# Ctrl+[ opens a menu of sections, each on a letter, and the menu keeps a few
# letters for functions of its own — N is "new section", the way to name one
# that isn't listed. The letters for the sections used to be counted a, b, c…
# straight through, so with fourteen of them the fourteenth landed on N and
# replaced it in the keymap: the menu then drew two rows under N and there was
# no way left to name a new section. Fourteen sections is an ordinary
# afternoon's work.
#
# This gives a kit type a `sections` list long enough to reach N, opens the
# real menu in a real browser, and reads back the rows it drew. The unit tests
# next to menu_keys.js cover the letter arithmetic; this covers the wiring —
# that the menu really does hand its keymap over before the letters are dealt.
#
#   1. Start the repl server in another terminal:
#         bin/repl
#
#   2. Run this script:
#         bundle exec ruby script/section_menu_auto.rb
#
# Exit codes: 0 = PASS, 1 = FAIL.

ENV["RAILS_ENV"] ||= "repl"

require_relative "transcription_repl_lib"

TranscriptionReplLib.require_server!
require_relative "../config/environment"
TranscriptionReplLib.bootstrap_db_if_needed!

# 'new' first is what makes the menu offer "new section" at all — open_section2
# reads it off the front of the list. Then seventeen names, which is past the
# fourteen it takes to reach N and past the letter R as well.
SECTIONS = %w[
  new
  alpha bravo charlie delta echo foxtrot golf hotel india
  juliett kilo lima mike november oscar papa quebec
].freeze
FOURTEENTH = "november".freeze # the name that used to collide with "new section"

puts "==> Setting up data (a kit type with #{SECTIONS.length - 1} sections)..."
ctx = TranscriptionReplLib.setup_data(
  kit_type_name: "transcription_repl_sections",
  name_suffix: "_sections",
  extra_constraints: { "sections" => SECTIONS }
)

puts ""
puts "==> Launching Chrome..."
driver = TranscriptionReplLib.launch_browser_signed_in(
  user: ctx[:user], task_user: ctx[:task_user], task: ctx[:task]
)
at_exit { driver.quit rescue nil }
wait = Selenium::WebDriver::Wait.new(timeout: 30)

passes   = []
failures = []
check = ->(label, ok) { ok ? passes << label : failures << label }

# A segment, because a section is opened on one. Same gesture the main harness
# uses: set the selection through the waveform controller, then Enter.
puts "==> Making a segment to open a section on..."
wait.until { driver.find_elements(css: "canvas.waveform-waveform.active").any? }
sleep 0.5
wait.until { driver.execute_script("return !!(window.ldc && window.ldc.wc && window.ldc.wc.set_current_selection)") }

keyboard = driver.find_element(css: ".keyboard")
driver.execute_script("window.ldc.wc.set_current_selection(arguments[0], arguments[1])", 0.5, 1.5)
sleep 0.2
keyboard.click
keyboard.send_keys(:enter)
wait.until { driver.find_elements(css: "#segments .segment").any? }
wait.until do
  segs = driver.find_elements(css: "#segments .segment")
  segs.last && segs.last.attribute("class").to_s.include?("active-segment")
end
textarea = wait.until { driver.find_element(css: "#segments .segment.active-segment textarea.ann-segment") }
textarea.send_keys("a segment to hang a section on")
sleep 0.4

# Ctrl+[ as a synthetic keydown on the textarea, for the same reason the main
# harness does it that way: a real Ctrl+[ would be handled by the OS first.
puts "==> Opening the section menu (Ctrl+[)..."
driver.execute_script(<<~JS)
  const ta = document.querySelector('#segments .segment.active-segment textarea.ann-segment');
  if (!ta) throw new Error('no active textarea — cannot open the section menu');
  ta.focus();
  ta.dispatchEvent(new KeyboardEvent('keydown', {
    key: '[', code: 'BracketLeft', ctrlKey: true, bubbles: true, cancelable: true,
  }));
JS
sleep 0.5

# The help screen draws one <li> per row: a <span> holding the letter, then the
# label. Read them back rather than trusting what we think was bound.
rows = driver.execute_script(<<~JS)
  return Array.from(document.querySelectorAll('li.mb-1')).map((li) => {
    const span = li.querySelector('span');
    const key = span ? span.textContent.trim() : '';
    return [ key, li.textContent.trim().replace(new RegExp('^' + key + '\\\\s*'), '') ];
  });
JS

puts ""
puts "==> The menu, as drawn:"
rows.each { |key, label| puts format("    %-4s %s", key.to_s.empty? ? "—" : key, label) }
puts ""

keys      = rows.map(&:first).reject { |k| k.to_s.empty? }
new_row   = rows.find { |_, label| label.to_s.include?("new section") }
collided  = rows.find { |_, label| label == FOURTEENTH }

check.call("the menu drew a row for every section, plus 'new section' (#{rows.length})",
           rows.length == SECTIONS.length)
check.call("'new section' is on the menu", !new_row.nil?)
check.call("…and it still answers to N (#{new_row&.first.inspect})",
           new_row && new_row.first.to_s.downcase == "n")
check.call("no letter was handed out twice",
           keys.uniq.length == keys.length)
check.call("the fourteenth section stepped over N onto O (#{collided&.first.inspect})",
           collided && collided.first.to_s.downcase == "o")
check.call("every section got a letter",
           rows.none? { |key, _| key.to_s.empty? })
# Reading the constraint list past its end used to put a row named "undefined"
# on every menu a kit type constrained.
check.call("no row is labelled 'undefined'",
           rows.none? { |_, label| label.to_s.include?("undefined") })

# And the letter really does what the row says: press it and the section opens.
puts "==> Pressing O, the letter the fourteenth section now answers to..."
driver.execute_script(<<~JS)
  document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {
    key: 'o', code: 'KeyO', bubbles: true, cancelable: true,
  }));
JS
sleep 0.8
# secmap is what the transcript renders sections from; the Section table is a
# projection that only exists once the kit is snapshotted, so it has nothing to
# say yet.
opened = driver.execute_script("return Array.from(window.ldc.secmap.values()).map((s) => s.section)")
check.call("pressing it opened a section, and the section it opened is #{FOURTEENTH.inspect} (#{opened.inspect})",
           opened.include?(FOURTEENTH))

driver.quit rescue nil

puts ""
puts "==> The section menu's letters"
passes.each   { |l| puts "  \e[32mPASS\e[0m #{l}" }
failures.each { |l| puts "  \e[31mFAIL\e[0m #{l}" }
puts ""
if failures.empty?
  puts "PASS (#{passes.length} checks)"
  exit 0
else
  puts "FAIL (#{failures.length} of #{passes.length + failures.length} checks failed)"
  exit 1
end
