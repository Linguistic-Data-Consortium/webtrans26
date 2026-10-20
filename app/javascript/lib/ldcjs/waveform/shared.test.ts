import { beforeEach, describe, expect, test } from "vitest";
import { set_reference_text, get_reference_text, clear_reference_text } from "./shared.svelte";

// The "blanks" import stores each reference segment's text and time span, and
// the segment list shows it above the segments it *overlaps* (via
// get_reference_text(x.beg, x.end)). These tests pin the overlap criterion so a
// caption stays with a segment even when its extent is nudged, and so touching
// endpoints don't cross-match adjacent segments.
describe("reference text store (blanks import, overlap match)", () => {
  beforeEach(() => clear_reference_text());

  test("returns text for a segment that fully covers the reference", () => {
    set_reference_text(5, 8, "hello there");
    expect(get_reference_text(5, 8)).toBe("hello there");
  });

  test("matches on partial overlap (e.g. after the extent is nudged)", () => {
    set_reference_text(5, 8, "drifted");
    expect(get_reference_text(5.2, 8.3)).toBe("drifted"); // overlaps [5,8]
    expect(get_reference_text(4.5, 5.5)).toBe("drifted"); // overlaps [5,8]
  });

  test("does not match a non-overlapping segment", () => {
    set_reference_text(5, 8, "hi");
    expect(get_reference_text(8.5, 9)).toBeUndefined();
    expect(get_reference_text(3, 4.9)).toBeUndefined();
  });

  test("touching endpoints do not count as overlap", () => {
    set_reference_text(5, 8, "hi");
    expect(get_reference_text(8, 9)).toBeUndefined(); // starts exactly where ref ends
    expect(get_reference_text(3, 5)).toBeUndefined(); // ends exactly where ref begins
  });

  test("joins every overlapping reference in time order", () => {
    set_reference_text(5, 8, "first");
    set_reference_text(8.5, 11, "second");
    // a segment spanning both references shows both captions, in beg order
    expect(get_reference_text(4, 12)).toBe("first second");
  });

  test("clear removes all references", () => {
    set_reference_text(1, 2, "x");
    clear_reference_text();
    expect(get_reference_text(1, 2)).toBeUndefined();
  });
});
