import { beforeEach, describe, expect, test } from "vitest";
import { BATCH_SIZE, bulko, bulk_start, bulk_after_paint, bulk_total, bulk_done, bulk_end } from "./bulk.svelte";

// The segment list hides the transcript whenever `label` is set, so the states
// that matter are: is something running, and is there a count worth showing.
// A run that fails to clear `label` hides the transcript until a reload.
describe("bulk progress", () => {
  beforeEach(() => bulk_end());

  test("nothing is running to begin with", () => {
    expect(bulko.label).toBe(null);
  });

  test("a run with a known size reports a count from the start", () => {
    bulk_start("Deleting segments", 40);

    expect(bulko.label).toBe("Deleting segments");
    expect(bulko.total).toBe(40);
    expect(bulko.done).toBe(0);
  });

  test("a run whose size isn't known yet has no total", () => {
    bulk_start("Running ASR");

    expect(bulko.label).toBe("Running ASR");
    expect(bulko.total).toBe(0);
  });

  test("the size and the label can arrive part-way through", () => {
    bulk_start("Running ASR");
    bulk_total(250, "Loading segments");

    expect(bulko.label).toBe("Loading segments");
    expect(bulko.total).toBe(250);
  });

  test("bulk_total keeps the label when none is given", () => {
    bulk_start("Running ASR");
    bulk_total(250);

    expect(bulko.label).toBe("Running ASR");
    expect(bulko.total).toBe(250);
  });

  test("progress advances", () => {
    bulk_start("Deleting segments", 40);
    bulk_done(10);
    bulk_done(20);

    expect(bulko.done).toBe(20);
  });

  // The ASR loop reports -1 before its first batch, and an off-by-one anywhere
  // would otherwise show a count past the total or a bar over 100%.
  test("a negative count clamps to zero", () => {
    bulk_start("Loading segments", 40);
    bulk_done(-1);

    expect(bulko.done).toBe(0);
  });

  test("a count past the total clamps to the total", () => {
    bulk_start("Loading segments", 40);
    bulk_done(45);

    expect(bulko.done).toBe(40);
  });

  test("ending a run releases the panel", () => {
    bulk_start("Deleting segments", 40);
    bulk_done(40);
    bulk_end();

    expect(bulko.label).toBe(null);
    expect(bulko.done).toBe(0);
    expect(bulko.total).toBe(0);
  });

  test("ending is safe when nothing was running", () => {
    bulk_end();
    bulk_end();

    expect(bulko.label).toBe(null);
  });

  test("a second run replaces the first rather than stacking", () => {
    bulk_start("Running ASR");
    bulk_done(5);
    bulk_start("Deleting segments", 12);

    expect(bulko.label).toBe("Deleting segments");
    expect(bulko.total).toBe(12);
    expect(bulko.done).toBe(0);
  });
});

// All three batched operations walk their work the same way — ASR's xasrrr,
// delete_batch and change_batch are the same loop over the same size — so the
// progress the panel shows means the same thing whichever is running. This
// models that loop; the real ones live in asr.svelte.js and modification1.js.
describe("batching", () => {
  const steps = (total: number) => {
    const reported: number[] = [];
    for (let i = 0; i < total; ) {
      let j = i;
      while (j < i + BATCH_SIZE && j < total) j++;
      reported.push(j);
      i = j;
    }
    return reported;
  };

  test("one round trip per BATCH_SIZE items", () => {
    expect(steps(250)).toEqual([100, 200, 250]);
  });

  test("the last batch reports the total, not a multiple", () => {
    expect(steps(250).at(-1)).toBe(250);
    expect(steps(100).at(-1)).toBe(100);
  });

  // Why the panel shows a label even when it can't show a bar: an operation
  // under one batch has nothing to report until it is done.
  test("fewer items than one batch is a single step", () => {
    expect(steps(40)).toEqual([40]);
  });

  test("no work is no steps", () => {
    expect(steps(0)).toEqual([]);
  });

  // A 300-segment delete was 30 round trips at the old size of ten.
  test("the size that used to differ per operation is now one number", () => {
    expect(BATCH_SIZE).toBe(100);
    expect(steps(300).length).toBe(3);
  });
});

// bulk_start only sets state; nothing is drawn until the task yields. The
// operations that call it used to go straight into a hundred immutable graph
// updates, so the panel announcing the work appeared after the first batch of
// it — the app looked hung at the moment the annotator asked for something.
describe("bulk_after_paint", () => {
  test("defers to a frame when there is one", () => {
    const frames: Array<() => void> = [];
    vi.stubGlobal("requestAnimationFrame", (f: () => void) => { frames.push(f); return 0; });
    const work = vi.fn();

    bulk_after_paint(work);
    expect(work).not.toHaveBeenCalled();   // the paint comes first

    frames.forEach((f) => f());
    expect(work).toHaveBeenCalledTimes(1);

    vi.unstubAllGlobals();
  });

  // A test runner or any non-browser caller still has to complete.
  test("runs the work directly when there is no frame loop", () => {
    vi.stubGlobal("requestAnimationFrame", undefined);
    const work = vi.fn();

    bulk_after_paint(work);

    expect(work).toHaveBeenCalledTimes(1);
    vi.unstubAllGlobals();
  });
});
