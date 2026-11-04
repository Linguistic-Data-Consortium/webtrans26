import { describe, expect, test } from "vitest";
import { drop_overlapping, span_problem, rows_to_spans, stretch_label, offset_segments } from "./spans";

describe("drop_overlapping", () => {
  const existing = [
    { docid: "a", beg: 1, end: 2 },
    { docid: "b", beg: 5, end: 6 },
    { docid: "a", beg: 8, end: 9, readonly: true }
  ];
  const docid_of = (s: any) => s.channel == "ch_1" ? "b" : "a";

  test("skips what touches an existing segment on the same docid", () => {
    const segs = [
      { beg: 1.5, end: 3, channel: "ch_0" },   // overlaps a's 1–2
      { beg: 3, end: 4, channel: "ch_0" },     // clear
      { beg: 5.5, end: 7, channel: "ch_0" },   // b's segment is on the other channel
      { beg: 5.5, end: 7, channel: "ch_1" },   // overlaps b's 5–6
      { beg: 8.5, end: 9.5, channel: "ch_0" }  // a reference caption doesn't count
    ];
    const r = drop_overlapping(segs, existing, docid_of);
    expect(r.skipped).toBe(2);
    expect(r.kept.map((s) => s.beg)).toEqual([3, 5.5, 8.5]);
  });

  test("abutting is not overlapping", () => {
    const r = drop_overlapping([{ beg: 2, end: 3, channel: "ch_0" }], existing, docid_of);
    expect(r.skipped).toBe(0);
  });
});

describe("span_problem", () => {
  test("a good span has none", () => {
    expect(span_problem({ beg: 0, end: 1, docid: "d" })).toBeNull();
    expect(span_problem({ beg: 1.5, end: 2, docid: "d", text: "hi" })).toBeNull();
  });
  test("says what's wrong", () => {
    expect(span_problem(null)).toBe("not an object");
    expect(span_problem({ beg: 0, end: 1 })).toBe("no docid");
    expect(span_problem({ beg: "0", end: 1, docid: "d" })).toBe("beg and end must be numbers");
    expect(span_problem({ beg: -1, end: 1, docid: "d" })).toBe("begins before zero");
    expect(span_problem({ beg: 2, end: 2, docid: "d" })).toBe("ends before it begins");
    expect(span_problem({ beg: 0, end: 1, docid: "d", text: 5 })).toBe("text must be a string");
  });
});

describe("rows_to_spans", () => {
  // As xasr_process makes them, for a run that previews instead of adding.
  test("rows into spans, with their text, times to the millisecond", () => {
    expect(rows_to_spans([
      { docid: "d", offset: 1.23456, length: 2, transcript: " Hello there. " },
      { docid: "d", offset: 4, length: 1, transcript: "" }
    ])).toEqual([
      { beg: 1.235, end: 3.235, docid: "d", text: "Hello there." },
      { beg: 4, end: 5, docid: "d" }
    ]);
  });
  test("what can't be a span is left out", () => {
    expect(rows_to_spans([{ docid: "d", offset: 2, length: 0 }, { offset: 1, length: 1 }])).toEqual([]);
  });
});

describe("stretch_label", () => {
  test("names a bounded run's stretch, and nothing for the whole recording", () => {
    expect(stretch_label(null)).toBe("");
    expect(stretch_label({ beg: 0, end: Infinity })).toBe("");
    expect(stretch_label({ beg: 30, end: Infinity })).toBe(" · 30–end s");
    expect(stretch_label({ beg: 0, end: 12.5 })).toBe(" · 0–12.5 s");
  });
});

describe("offset_segments", () => {
  test("times from a stretch's start become times from the recording's, the rest kept", () => {
    expect(offset_segments([{ beg: 0.25, end: 1.5, text: "hi", channel: "ch_0" }], 30))
      .toEqual([{ beg: 30.25, end: 31.5, text: "hi", channel: "ch_0" }]);
    expect(offset_segments([{ beg: 0.1, end: 0.2 }], 0.2)).toEqual([{ beg: 0.3, end: 0.4 }]);
  });
});

