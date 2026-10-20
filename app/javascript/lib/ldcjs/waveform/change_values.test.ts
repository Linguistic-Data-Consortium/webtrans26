import { beforeEach, describe, expect, test, vi } from "vitest";

// The write primitives, so this tests the batching rather than the transport.
// add_callback is what sequences the batches in the real thing — each is queued
// after the previous submit resolves — so running it synchronously here walks the
// whole operation in one go.
const add_message = vi.fn();
const submit_form = vi.fn();
const add_callback = vi.fn((f: () => void) => f());

// change_values hands the browser a paint before the first batch
// (bulk_after_paint). These tests are about the batching, so run the frame
// straight away; the yield itself is covered in bulk.test.ts.
vi.stubGlobal("requestAnimationFrame", (f: () => void) => { f(); return 0; });

vi.mock("./modification2", () => ({
  add_message: (...a: unknown[]) => add_message(...a),
  add_message_listitem: vi.fn(),
  submit_form: () => submit_form(),
  add_callback: (f: () => void) => add_callback(f),
  setldc: vi.fn(),
}));
vi.mock("./shared.svelte", () => ({ sourceso: {}, sourcesor: {} }));
vi.mock("./transcript.svelte", () => ({ touch_segments: vi.fn() }));
vi.mock("../../../guides/guide", () => ({ event: { dispatch: vi.fn() } }));

import { BATCH_SIZE, bulko } from "./bulk.svelte";
import { change_values } from "./modification1";

// Replacing a speaker label across a transcript used to call change_value per
// row, and change_value submits per call — one round trip for every segment
// carrying that speaker. It batches now, at the same size as the ASR add loop
// and the delete, so the progress panel means the same thing for all three.
describe("change_values", () => {
  beforeEach(() => {
    add_message.mockClear();
    submit_form.mockClear();
    add_callback.mockClear();
  });

  const iids = (n: number) => Array.from({ length: n }, (_, i) => i + 1);

  test("sends one change per iid, with the value", () => {
    change_values([ 7, 8, 9 ], "subject", null, "Replacing speaker labels");

    expect(add_message).toHaveBeenCalledTimes(3);
    expect(add_message).toHaveBeenNthCalledWith(1, 7, "change", { value: "subject" });
    expect(add_message).toHaveBeenNthCalledWith(3, 9, "change", { value: "subject" });
  });

  test("one round trip per batch, not per row", () => {
    change_values(iids(250), "x", null, "l");

    expect(add_message).toHaveBeenCalledTimes(250);
    expect(submit_form).toHaveBeenCalledTimes(3);
  });

  test("a single batch is a single round trip", () => {
    change_values(iids(BATCH_SIZE), "x", null, "l");

    expect(submit_form).toHaveBeenCalledTimes(1);
  });

  test("nothing to change does nothing at all", () => {
    change_values([], "x", null, "l");

    expect(add_message).not.toHaveBeenCalled();
    expect(submit_form).not.toHaveBeenCalled();
    // And no panel: it would show for a frame and report 0 of 0.
    expect(bulko.label).toBe(null);
  });

  test("the panel is released when the last batch lands", () => {
    change_values(iids(150), "x", null, "Replacing speaker labels");

    expect(bulko.label).toBe(null);
  });

  // The callback rebuilds the transcript rows and, through index_segments, sets
  // the active line. Nothing of that is visible while the progress panel is up,
  // so it runs once at the end rather than per batch — three folds of the whole
  // transcript saved on a 250-row replace, and 250 on what it cost before.
  test("the caller's render callback runs once, not per batch", () => {
    const f = vi.fn();
    change_values(iids(250), "x", f, "l");

    expect(f).toHaveBeenCalledTimes(1);
  });

  test("and after the panel is down, so the list is rebuilt visible", () => {
    const order: string[] = [];
    // bulko.label is cleared by bulk_end; record what the callback sees.
    change_values(iids(150), "x", () => order.push(bulko.label ? "panel up" : "panel down"), "l");

    expect(order).toEqual([ "panel down" ]);
  });
});
