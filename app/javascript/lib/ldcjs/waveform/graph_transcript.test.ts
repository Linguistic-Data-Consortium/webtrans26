import { describe, expect, test } from "vitest";
import {
  graph_rows,
  graph_segments,
  graph_undefined_segments,
  graph_sections,
  compare_segments,
} from "./graph_transcript";

// A graph as /kits/graph returns it: two anchors and a segment spanning them,
// with Text and Speaker labels.
const graph = {
  nodes: [
    { iid: 10, n_iid: 11, docid: "a.wav", time: 1.25 },
    { iid: 12, n_iid: 13, docid: "a.wav", time: 3.5 },
    { iid: 20, n_iid: 21, docid: "a.wav", time: 4.0 },
    { iid: 22, n_iid: 23, docid: "a.wav", time: 6.5 },
  ],
  arcs: [
    { iid: 24, name: "SegmentListItem", arc_node_iid: 25, beg_iid: 20, end_iid: 22 },
    { iid: 14, name: "SegmentListItem", arc_node_iid: 15, beg_iid: 10, end_iid: 12 },
    { iid: 30, name: "SectionListItem", arc_node_iid: 31, beg_iid: 10, end_iid: 22 },
  ],
  labels: [
    { iid: 16, arc_iid: 14, name: "Text", value: "first line" },
    { iid: 17, arc_iid: 14, name: "Speaker", value: "alice" },
    { iid: 26, arc_iid: 24, name: "Text", value: "second line" },
    { iid: 32, arc_iid: 30, name: "Name", value: "intro" },
  ],
};

// What transcribe_text_only asks before creating its segments. It has to be
// the spans, not the nodes: deleting a segment leaves the anchors its times
// pointed at, so a kit that once held one still has nodes in it and would
// never be given segments again.
describe("graph_rows as the emptiness test", () => {
  test("anchors with no span left is an empty kit", () => {
    const orphaned = {
      nodes: [
        { iid: 10, n_iid: 11, docid: "a.wav", time: 1.25 },
        { iid: 12, n_iid: 13, docid: "a.wav", time: 3.5 },
      ],
      arcs: [],
      labels: [],
    };
    expect(graph_rows(orphaned, "SegmentListItem")).toHaveLength(0);
  });

  test("a span with no times yet still counts as a segment", () => {
    const unplaced = {
      nodes: [],
      arcs: [{ iid: 14, name: "SegmentListItem", arc_node_iid: 15, beg_iid: null, end_iid: null }],
      labels: [],
    };
    expect(graph_rows(unplaced, "SegmentListItem")).toHaveLength(1);
  });

  test("a section doesn't make a kit non-empty of segments", () => {
    expect(graph_rows({ nodes: [], arcs: [ { iid: 30, name: "SectionListItem" } ], labels: [] }, "SegmentListItem"))
      .toHaveLength(0);
  });
});

describe("graph_segments", () => {
  test("one row per segment arc, in time order, with its labels", () => {
    expect(graph_segments(graph)).toEqual([
      { iid: 14, arc_node_iid: 15, beg: 1.25, end: 3.5, text: "first line", speaker: "alice", label: "" },
      { iid: 24, arc_node_iid: 25, beg: 4.0, end: 6.5, text: "second line", speaker: "", label: "" },
    ]);
  });

  test("times are resolved through the anchors the arc points at", () => {
    const moved = { ...graph, nodes: graph.nodes.map((n) => (n.iid === 10 ? { ...n, time: 0.5 } : n)) };
    expect(graph_segments(moved)[0].beg).toBe(0.5);
  });

  test("sections are separate from segments", () => {
    expect(graph_segments(graph).map((r) => r.iid)).not.toContain(30);
    expect(graph_sections(graph)).toEqual([
      { iid: 30, arc_node_iid: 31, beg: 1.25, end: 6.5, text: "", speaker: "", label: "intro" },
    ]);
  });

  test("an arc whose anchors have no time yet is undefined, not a row", () => {
    const untimed = {
      ...graph,
      nodes: graph.nodes.map((n) => (n.iid === 20 ? { ...n, time: null } : n)),
    };
    expect(graph_segments(untimed).map((r) => r.iid)).toEqual([14]);
    expect(graph_undefined_segments(untimed)).toEqual([24]);
  });

  test("an empty graph derives to nothing", () => {
    const empty = { nodes: [], arcs: [], labels: [] };
    expect(graph_segments(empty)).toEqual([]);
    expect(graph_sections(empty)).toEqual([]);
    expect(graph_segments({} as any)).toEqual([]);
  });
});

describe("compare_segments", () => {
  const live = [
    { iid: 14, beg: 1.25, end: 3.5, text: "first line", speaker: "alice" },
    { iid: 24, beg: 4.0, end: 6.5, text: "second line", speaker: "" },
  ];

  test("agrees with the live transcript built the other way", () => {
    const result = compare_segments(live, graph_segments(graph));
    expect(result.matches).toBe(true);
    expect(result.compared).toBe(2);
  });

  test("reports a row the graph is missing", () => {
    const result = compare_segments(live, graph_segments(graph).slice(0, 1));
    expect(result.matches).toBe(false);
    expect(result.only_live).toEqual([24]);
  });

  test("reports a row only the graph has", () => {
    const result = compare_segments(live.slice(0, 1), graph_segments(graph));
    expect(result.only_derived).toEqual([24]);
  });

  test("reports which fields differ", () => {
    const edited = live.map((r) => (r.iid === 14 ? { ...r, text: "edited", beg: 9 } : r));
    const result = compare_segments(edited, graph_segments(graph));
    expect(result.differing).toEqual([{ iid: 14, fields: ["beg", "text"] }]);
  });

  test("a float and a decimal of the same time still agree", () => {
    const rounded = live.map((r) => (r.iid === 14 ? { ...r, beg: 1.2500001 } : r));
    expect(compare_segments(rounded, graph_segments(graph)).matches).toBe(true);
  });

  test("empty and null text are the same thing", () => {
    const blank = [{ iid: 14, beg: 1.25, end: 3.5, text: null, speaker: null }];
    const derived = [{ iid: 14, beg: 1.25, end: 3.5, text: "", speaker: "" }];
    expect(compare_segments(blank as any, derived).matches).toBe(true);
  });

  // The blanks import adds reference rows client-side; they never reach the
  // log, so the graph can't have them and they aren't a disagreement.
  test("client-only rows are skipped", () => {
    const with_reference = [ ...live, { iid: 99, beg: 0, end: 1, text: "reference", readonly: true } ];
    expect(compare_segments(with_reference, graph_segments(graph)).matches).toBe(true);
  });
});
