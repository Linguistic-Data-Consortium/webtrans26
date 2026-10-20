import { render } from "@testing-library/svelte";
import { tick } from "svelte";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

// The LDC guide module runs `window.Guide.reset = ...` at import time, which
// throws under jsdom. channels.svelte only needs `event.dispatch` from it.
vi.mock("../../../guides/guide", () => ({ event: { dispatch: vi.fn() } }));

// The edge keys persist by re-timing an anchor: a change message naming the
// anchor's N node. Capture the messages rather than the network.
const add_message = vi.fn();
vi.mock("./modification2", () => ({
  add_message: (...args: unknown[]) => add_message(...args),
  add_message_listitem: vi.fn(),
  submit_form: vi.fn(),
  add_callback: vi.fn(),
  setldc: vi.fn(),
}));

import Channels from "./channels.svelte";
import { set_ldc } from "./modification1";
import { activeo } from "./shared.svelte";

// Regression test for the keyboard segment-extent bug.
//
// In Selection mode the edge keys (d/f = begin, j/k = end) call the exported
// move_beg_*/move_end_* functions -> move_selection_edge(). The bug was that
// move_selection_edge() called set_current_selection() (which only moves the
// on-screen selection) instead of wave_update() (which persists the new times
// to the active transcript line via update_node and then submits). So keyboard
// edge edits were silently discarded, while the mouse edge-drag path — which
// goes through wave_update — saved correctly.
//
// These tests mount channels.svelte with nchannels: 0 (no child canvases),
// establish a selection plus an active transcript line, invoke the exported
// keyboard action, and assert the persistence path fires. They fail against
// the old set_current_selection routing and pass once it routes through
// wave_update.

function baseProps(overrides = {}) {
  return {
    ldc: {},
    nchannels: 0, // render no <Channel> children (avoids canvas)
    underline: () => {},
    wave_canvas_height: 100,
    width: 800,
    create_audio_hash_from_docid: () => {},
    create_audiok_from_docid: () => {},
    docids: ["doc0"],
    debug: false,
    redact_task: false,
    set_current_selection: vi.fn((o, l) => {
      // mirror the real setter so selection state stays consistent
      activeo.wave_selection_offset = o;
      activeo.wave_selection_length = l;
    }),
    controls: { keyboard_focus: () => {} },
    wave_active_transcript_line: "node-7",
    set_active_transcript_line_helper: vi.fn(),
    duration: 100,
    play_head: 0,
    wmap: new Map([["node-7", "seg-7"]]),
    source_uid_channels: [],
    segmentsc: { set_active_transcript_line: vi.fn() },
    ...overrides,
  };
}

describe("channels.svelte keyboard extent adjustment", () => {
  beforeEach(() => {
    add_message.mockClear();
    // The row the active line maps to, as refold_graph builds it: the two
    // anchors its span runs between. update_node re-times one of them.
    set_ldc({ segmap: new Map([[7, { iid: 7, begi: 10, endi: 12 }]]) });
    // A visible window [0, 20] with a selection [5, 8] that maps to node-7.
    activeo.wave_display_offset = 0;
    activeo.wave_display_length = 20;
    activeo.wave_selection_offset = 5;
    activeo.wave_selection_length = 3; // end = 8
    activeo.channel = 0;
    activeo.active = "node-7";
  });

  afterEach(() => {
    activeo.wave_selection_offset = null;
    activeo.wave_selection_length = 0;
  });

  test("move_end_right persists the new end time to the active line", async () => {
    const props = baseProps();
    const { component } = render(Channels, { props });
    await tick();

    // j/k end-edge key: nudge the end edge right by step1 (0.1s): 8 -> 8.1
    component.move_end_right();
    await tick();

    // The whole point: keyboard edits must reach the persistence path. The end
    // edge moves the end anchor (12), whose time lives on its N child (13).
    expect(add_message).toHaveBeenCalledTimes(1);
    expect(add_message).toHaveBeenCalledWith(13, "change", { docid: "doc0", beg: 8.1, type: "real" });
  });

  test("move_beg_right persists the new begin time to the active line", async () => {
    const props = baseProps();
    const { component } = render(Channels, { props });
    await tick();

    // d/f begin-edge key: nudge the begin edge right by step1: 5 -> 5.1
    component.move_beg_right();
    await tick();

    // The begin edge moves the begin anchor (10) via its N child (11).
    expect(add_message).toHaveBeenCalledTimes(1);
    expect(add_message).toHaveBeenCalledWith(11, "change", { docid: "doc0", beg: 5.1, type: "real" });
  });

  test("does nothing when there is no selection", async () => {
    activeo.wave_selection_offset = null;
    const props = baseProps();
    const { component } = render(Channels, { props });
    await tick();

    component.move_end_right();
    await tick();

    expect(add_message).not.toHaveBeenCalled();
  });
});
