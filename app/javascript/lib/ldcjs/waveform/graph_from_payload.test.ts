import { describe, expect, test } from "vitest";
import { writable } from "svelte/store";
import { graph_from_payload, graph_from_nodes } from "./graph_from_payload";
import { graph_segments, graph_sections } from "./graph_transcript";

// A kit payload as /kits/get sends it: the tree folded flat. Two anchors and a
// segment spanning them, plus a section over the same span.
//
//   10:NListItem,11:N      at 1.25
//   12:NListItem,13:N      at 3.5
//   14:SegmentListItem,15:Arc,16:Text,17:Speaker
//   30:SectionListItem,31:Arc,32:Name
const payload = {
  nodes: [
    { iid: 10, name: "NListItem", parent_iid: null, index: null, level: 2, annotation_id: 100 },
    { iid: 11, name: "N", parent_iid: 10, index: 0, level: 3, annotation_id: 101 },
    { iid: 12, name: "NListItem", parent_iid: null, index: null, level: 2, annotation_id: 102 },
    { iid: 13, name: "N", parent_iid: 12, index: 0, level: 3, annotation_id: 103 },
    { iid: 14, name: "SegmentListItem", parent_iid: null, index: null, level: 2, annotation_id: 104 },
    { iid: 15, name: "Arc", parent_iid: 14, index: 0, level: 3, annotation_id: 105 },
    { iid: 16, name: "Text", parent_iid: 14, index: 1, level: 3, annotation_id: 106 },
    { iid: 17, name: "Speaker", parent_iid: 14, index: 2, level: 3, annotation_id: 107 },
    { iid: 30, name: "SectionListItem", parent_iid: null, index: null, level: 2, annotation_id: 108 },
    { iid: 31, name: "Arc", parent_iid: 30, index: 0, level: 3, annotation_id: 109 },
    { iid: 32, name: "Name", parent_iid: 30, index: 1, level: 3, annotation_id: 110 },
  ],
  node_values: [
    { id: 100, value: "10:NListItem,11:N", docid: null, beg: 0, end: 0 },
    { id: 101, value: null, docid: "a.wav", beg: 1.25, end: 0 },
    { id: 102, value: "12:NListItem,13:N", docid: null, beg: 0, end: 0 },
    { id: 103, value: null, docid: "a.wav", beg: 3.5, end: 0 },
    { id: 104, value: "14:SegmentListItem,15:Arc,16:Text,17:Speaker", docid: null, beg: 0, end: 0 },
    { id: 105, value: null, docid: null, beg: 10, end: 12 },
    { id: 106, value: "first line", docid: null, beg: 0, end: 0 },
    { id: 107, value: "alice", docid: null, beg: 0, end: 0 },
    { id: 108, value: "30:SectionListItem,31:Arc,32:Name", docid: null, beg: 0, end: 0 },
    { id: 109, value: null, docid: null, beg: 10, end: 12 },
    { id: 110, value: "intro", docid: null, beg: 0, end: 0 },
  ],
  last_iid: 32,
};

describe("graph_from_payload", () => {
  test("a group with an N is a time anchor", () => {
    expect(graph_from_payload(payload).nodes).toEqual([
      { iid: 10, n_iid: 11, docid: "a.wav", time: 1.25 },
      { iid: 12, n_iid: 13, docid: "a.wav", time: 3.5 },
    ]);
  });

  test("every other group is a span between two anchors", () => {
    expect(graph_from_payload(payload).arcs).toEqual([
      { iid: 14, name: "SegmentListItem", arc_node_iid: 15, beg_iid: 10, end_iid: 12 },
      { iid: 30, name: "SectionListItem", arc_node_iid: 31, beg_iid: 10, end_iid: 12 },
    ]);
  });

  test("the span's other children are labels on it", () => {
    expect(graph_from_payload(payload).labels).toEqual([
      { iid: 16, arc_iid: 14, name: "Text", value: "first line" },
      { iid: 17, arc_iid: 14, name: "Speaker", value: "alice" },
      { iid: 32, arc_iid: 30, name: "Name", value: "intro" },
    ]);
  });

  // The fold has to hold whatever the tree holds, not a fixed set of names.
  test("a class def with different children still folds", () => {
    const other = {
      nodes: [
        { iid: 40, name: "ThingListItem", parent_iid: null, level: 2, annotation_id: 200 },
        { iid: 41, name: "Arc", parent_iid: 40, level: 3, annotation_id: 201 },
        { iid: 42, name: "Colour", parent_iid: 40, level: 3, annotation_id: 202 },
      ],
      node_values: [
        { id: 200, value: "40:ThingListItem,41:Arc,42:Colour" },
        { id: 201, value: null, beg: 10, end: 12 },
        { id: 202, value: "blue" },
      ],
    };
    const graph = graph_from_payload(other);
    expect(graph.arcs).toEqual([{ iid: 40, name: "ThingListItem", arc_node_iid: 41, beg_iid: 10, end_iid: 12 }]);
    expect(graph.labels).toEqual([{ iid: 42, arc_iid: 40, name: "Colour", value: "blue" }]);
  });

  // Children start out pointing at annotation 0, the placeholder, which no
  // node_values entry covers.
  test("a child that was never changed has no value yet", () => {
    const fresh = {
      nodes: [
        { iid: 50, name: "SegmentListItem", parent_iid: null, level: 2, annotation_id: 300 },
        { iid: 51, name: "Arc", parent_iid: 50, level: 3, annotation_id: 0 },
        { iid: 52, name: "Text", parent_iid: 50, level: 3, annotation_id: 0 },
      ],
      node_values: [{ id: 300, value: "50:SegmentListItem,51:Arc,52:Text" }],
    };
    const graph = graph_from_payload(fresh);
    expect(graph.arcs).toEqual([{ iid: 50, name: "SegmentListItem", arc_node_iid: 51, beg_iid: null, end_iid: null }]);
    expect(graph.labels).toEqual([{ iid: 52, arc_iid: 50, name: "Text", value: null }]);
  });

  test("a child whose list item is gone doesn't become a group of its own", () => {
    const orphaned = {
      ...payload,
      nodes: payload.nodes.filter((n) => n.iid !== 14),
    };
    const graph = graph_from_payload(orphaned);
    expect(graph.arcs.map((a) => a.iid)).toEqual([30]);
    expect(graph.labels.map((l) => l.iid)).toEqual([32]);
  });

  test("an empty or absent payload folds to an empty graph", () => {
    const empty = { nodes: [], arcs: [], labels: [] };
    expect(graph_from_payload({ nodes: [], node_values: [] })).toEqual(empty);
    expect(graph_from_payload(undefined as any)).toEqual(empty);
  });

  // The point of the fold: what comes out describes the transcript on its own.
  test("the transcript derives from the fold", () => {
    const graph = graph_from_payload(payload);
    expect(graph_segments(graph)).toEqual([
      { iid: 14, arc_node_iid: 15, beg: 1.25, end: 3.5, text: "first line", speaker: "alice", label: "" },
    ]);
    expect(graph_sections(graph)).toEqual([
      { iid: 30, arc_node_iid: 31, beg: 1.25, end: 3.5, text: "", speaker: "", label: "intro" },
    ]);
  });

  // Both server routes key values differently — the log by annotation id, the
  // graph shape by the node's own iid — and the fold reads whichever through
  // annotation_id, so it can't tell them apart.
  test("it folds the graph-shaped payload identically", () => {
    const graph_shaped = {
      nodes: payload.nodes.map((n) => ({ ...n, annotation_id: n.iid, arc_node_iid: n.parent_iid })),
      node_values: payload.node_values.map((v, i) => ({ ...v, id: payload.nodes[i].iid })),
    };
    expect(graph_from_payload(graph_shaped)).toEqual(graph_from_payload(payload));
  });
});

// work/other.js unpacks the payload into ldc.nodes: the same tree, one entry
// per node, each level-3 node carrying its current value (its node_value store
// keeps it up to date). This is what the transcript is rendered from, so the
// fold has to say the same thing over it as over the payload it came from.
const as_node_layer = (p: typeof payload) => {
  const values = new Map(p.node_values.map((v) => [v.id, v]));
  return new Map(
    p.nodes.map((n) => [
      n.iid,
      n.level === 3 ? { ...n, value: values.get(n.annotation_id) } : { ...n },
    ]),
  );
};

describe("graph_from_nodes", () => {
  test("folds the live node layer the same way as the payload it came from", () => {
    expect(graph_from_nodes(as_node_layer(payload))).toEqual(graph_from_payload(payload));
  });

  // Regression. Each node mirrors its store into `value` via a subscriber, and
  // svelte queues subscribers when a store is set during another store's
  // notification — so the mirror lags exactly when a segment is being created.
  // Folding it gave a tree with no times, and no segment ever rendered.
  test("the store wins over a value field that hasn't caught up", () => {
    const nodes = as_node_layer(payload);
    const stale = { value: null, docid: "a.wav", beg: 0, end: 0 };
    nodes.get(11).value = stale;
    nodes.get(11).node_value = writable({ value: null, docid: "a.wav", beg: 1.25, end: 0 });
    expect(graph_from_nodes(nodes).nodes.find((n) => n.iid === 10).time).toBe(1.25);
  });

  test("an edited value shows up in the fold", () => {
    const nodes = as_node_layer(payload);
    nodes.get(16).value = { id: 106, value: "edited", docid: null, beg: 0, end: 0 };
    const graph = graph_from_nodes(nodes);
    expect(graph.labels.find((l) => l.iid === 16).value).toBe("edited");
  });

  test("a moved anchor shows up in the fold", () => {
    const nodes = as_node_layer(payload);
    nodes.get(11).value = { id: 101, value: null, docid: "a.wav", beg: 9.5, end: 0 };
    expect(graph_from_nodes(nodes).nodes.find((n) => n.iid === 10).time).toBe(9.5);
  });

  // deletef removes the list item and its children from the map.
  test("a deleted segment leaves the fold", () => {
    const nodes = as_node_layer(payload);
    for (const iid of [14, 15, 16, 17]) nodes.delete(iid);
    const graph = graph_from_nodes(nodes);
    expect(graph.arcs.map((a) => a.iid)).toEqual([30]);
    expect(graph.labels.map((l) => l.iid)).toEqual([32]);
    expect(graph.nodes.map((n) => n.iid)).toEqual([10, 12]);
  });

  // addf builds the group client-side before the server has seen it: the list
  // item and its children exist with no values yet.
  test("a segment added client-side is a span with no times and empty labels", () => {
    const nodes = as_node_layer(payload);
    nodes.set(60, { iid: 60, name: "SegmentListItem", parent_iid: null, level: 2 });
    nodes.set(61, { iid: 61, name: "Arc", parent_iid: 60, level: 3, value: { value: "" } });
    nodes.set(62, { iid: 62, name: "Text", parent_iid: 60, level: 3, value: { value: "" } });
    const graph = graph_from_nodes(nodes);
    expect(graph.arcs.find((a) => a.iid === 60)).toEqual({
      iid: 60, name: "SegmentListItem", arc_node_iid: 61, beg_iid: null, end_iid: null,
    });
    expect(graph.labels.find((l) => l.iid === 62)).toEqual({
      iid: 62, arc_iid: 60, name: "Text", value: "",
    });
  });

  test("no node layer yet folds to an empty graph", () => {
    expect(graph_from_nodes(undefined as any)).toEqual({ nodes: [], arcs: [], labels: [] });
  });
});
