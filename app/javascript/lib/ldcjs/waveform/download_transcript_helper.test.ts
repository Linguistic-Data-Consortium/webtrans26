import { describe, expect, test, vi } from "vitest";
import { create_transcript, transcript_disagreement } from "./download_transcript_helper";

// Two anchored segments with Text and Speaker labels, and a section over both.
const graph = {
  nodes: [
    { iid: 10, n_iid: 11, docid: "a.wav", time: 1.25 },
    { iid: 12, n_iid: 13, docid: "a.wav", time: 3.5 },
    { iid: 20, n_iid: 21, docid: "a.wav", time: 4.0 },
    { iid: 22, n_iid: 23, docid: "a.wav", time: 6.5 },
  ],
  arcs: [
    { iid: 14, name: "SegmentListItem", arc_node_iid: 15, beg_iid: 10, end_iid: 12 },
    { iid: 24, name: "SegmentListItem", arc_node_iid: 25, beg_iid: 20, end_iid: 22 },
    { iid: 30, name: "SectionListItem", arc_node_iid: 31, beg_iid: 10, end_iid: 22 },
  ],
  labels: [
    { iid: 16, arc_iid: 14, name: "Text", value: "first line" },
    { iid: 17, arc_iid: 14, name: "Speaker", value: "alice" },
    { iid: 26, arc_iid: 24, name: "Text", value: "second line" },
    { iid: 27, arc_iid: 24, name: "Speaker", value: "bob" },
    { iid: 32, arc_iid: 30, name: "Name", value: "intro" },
  ],
};

// The live rows as refold_graph would have them: same tree, mutated in place.
const rows = () => [
  { iid: 14, beg: 1.25, end: 3.5, text: "first line", speaker: "alice", docid: "a.wav", section: null },
  { iid: 24, beg: 4.0, end: 6.5, text: "second line", speaker: "bob", docid: "a.wav", section: null },
];

// console.error carries the full comparison for whoever is debugging; the
// tests only care that the throw happened.
const quiet = () => vi.spyOn(console, "error").mockImplementation(() => {});

describe("transcript_disagreement", () => {
  test("rows that match the graph disagree about nothing", () => {
    expect(transcript_disagreement(rows(), graph)).toBeNull();
  });

  test("a row whose value drifted from the graph names the row and the field", () => {
    const segs = rows();
    segs[1].text = "stale text";
    const message = transcript_disagreement(segs, graph);
    expect(message).toMatch(/iid 24: text/);
  });

  test("a row the graph has and the transcript doesn't is reported", () => {
    const message = transcript_disagreement(rows().slice(0, 1), graph);
    expect(message).toMatch(/in the graph but not the transcript: 24/);
  });

  test("a row the transcript has and the graph doesn't is reported", () => {
    const segs = rows();
    segs.push({ iid: 44, beg: 8.0, end: 9.0, text: "ghost", speaker: "", docid: "a.wav", section: null });
    expect(transcript_disagreement(segs, graph)).toMatch(/in the transcript but not the graph: 44/);
  });

  test("read-only and virtual rows have no graph counterpart and are skipped", () => {
    const segs = rows();
    segs.push({ iid: 90, beg: 0.5, end: 1.0, text: "reference", speaker: "", readonly: true });
    segs.push({ iid: 91, beg: 0.5, end: 1.0, text: "", speaker: "", virtual: true });
    expect(transcript_disagreement(segs, graph)).toBeNull();
  });

  test("times from a decimal column and a float aren't a disagreement", () => {
    const segs = rows();
    segs[0].beg = 1.2500001;
    expect(transcript_disagreement(segs, graph)).toBeNull();
  });
});

describe("create_transcript", () => {
  test("writes the file when the two flattenings agree", () => {
    const tsv = create_transcript("kit-1", true, false, true, rows(), graph);
    expect(tsv).toMatch(/first line\talice/);
    expect(tsv).toMatch(/second line\tbob/);
  });

  test("throws instead of writing a file when they disagree", () => {
    const spy = quiet();
    const segs = rows();
    segs[0].text = "stale text";
    expect(() => create_transcript("kit-1", true, false, true, segs, graph)).toThrow(/disagree/);
    expect(spy).toHaveBeenCalled();
    spy.mockRestore();
  });

  test("no graph, no check — the dashboard has rows and nothing to check them against", () => {
    const segs = rows();
    segs[0].text = "stale text";
    const tsv = create_transcript("kit-1", true, false, true, segs);
    expect(tsv).toMatch(/stale text/);
  });
});
