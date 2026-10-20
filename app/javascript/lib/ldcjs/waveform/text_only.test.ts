import { beforeEach, describe, expect, test, vi } from "vitest";
import { lock_text_only, reset_text_only, text_only, text_only_refuses } from "./text_only";
import { text_only_forbidden, waveform_map, input_map } from "./bindings";

// transcribe_text_only: the segments came from an imported graph, so the
// operations that would change them don't run.
//
// Named per operation rather than per message. It was once a check on the
// messages themselves, which reads every message rather than every feature —
// 'done' is a message too, so closing a kit was refused along with the rest.
describe("text_only_refuses", () => {
  beforeEach(() => {
    reset_text_only();
    vi.spyOn(console, "warn").mockImplementation(() => {});
  });

  test("an ordinary kit refuses nothing", () => {
    expect(text_only()).toBe(false);
    expect(text_only_refuses("split a segment")).toBe(false);
    expect(text_only_refuses("create a segment")).toBe(false);
  });

  test("a locked kit refuses the operation and says which", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    lock_text_only();

    expect(text_only_refuses("split a segment")).toBe(true);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining("split a segment"));
  });

  test("the lock is one-way — a kit stays locked once its segments are in place", () => {
    lock_text_only();
    lock_text_only();

    expect(text_only()).toBe(true);
    expect(text_only_refuses("delete a segment")).toBe(true);
  });
});

// The list the keymaps and the segment list consult, so a gesture doesn't
// reach an operation that would only refuse.
describe("text_only_forbidden", () => {
  const actions = new Set<string>();
  const collect = (map: Record<string, unknown>) => {
    for (const [key, binding] of Object.entries(map)) {
      if (key === "control") continue;
      if (binding && typeof binding === "object" && "action" in binding) {
        actions.add((binding as { action: string }).action);
      }
    }
  };
  collect(waveform_map.cursor);
  collect(waveform_map.control.cursor);
  collect(input_map);
  collect(input_map.control);

  test("every forbidden action is one the keymaps actually bind", () => {
    expect([...text_only_forbidden].filter((a) => !actions.has(a))).toEqual([]);
  });

  test("the gestures that change shape are all covered", () => {
    for (const action of [
      "play_current_span_and_add_transcript_line_and_activate",
      "split_segment_at_cursor",
      "merge_with_following_segment",
      "delete_active_transcript_line",
      "set_speaker",
      "open_section",
    ]) {
      expect(text_only_forbidden.has(action)).toBe(true);
    }
  });

  test("moving around, playing and typing are left alone", () => {
    for (const action of [
      "play_current_span_or_play_stop",
      "move_cursor_lstep1",
      "set_active_transcript_line_to_next",
      "set_active_transcript_line_to_next_and_play_current_span",
      "zoom_in",
      "show_help_screen_main",
    ]) {
      expect(text_only_forbidden.has(action)).toBe(false);
    }
  });

  // Closing the kit is not an edit to the transcript. Refusing it was the bug
  // that moved this guard off the messages and onto the operations.
  test("closing the kit is not forbidden", () => {
    for (const action of [ "done", "broken", "skip" ]) {
      expect(text_only_forbidden.has(action)).toBe(false);
    }
  });
});
