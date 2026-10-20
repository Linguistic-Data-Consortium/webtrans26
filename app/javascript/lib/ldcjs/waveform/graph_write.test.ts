import { describe, expect, test } from "vitest";
import { writable } from "svelte/store";
import { apply_message, graph_difference, new_group } from "./graph_write";
import { graph_from_nodes } from "./graph_from_payload";
import { graph_segments } from "./graph_transcript";

const empty = () => ({ nodes: [], arcs: [], labels: [] });

// The message stream the tool sends when an annotator makes one segment: two
// anchors, then the span, then what's said about it. Exactly what reaches
// /annotations, in order.
const one_segment = [
  ["add", "0", { value: "1:NListItem,2:N" }],
  ["change", 2, { docid: "a.wav", beg: 0.5, type: "real" }],
  ["add", "0", { value: "3:NListItem,4:N" }],
  ["change", 4, { docid: "a.wav", beg: 2.0, type: "real" }],
  ["add", "0", { value: "5:SegmentListItem,6:Arc,7:Text,8:Speaker" }],
  ["change", 6, { beg: 1, end: 3 }],
  ["change", 7, { value: "some words" }],
  ["change", 8, { value: "alice" }],
] as const;

const play = (messages: readonly any[], start = empty()) =>
  messages.reduce((graph, [m, n, v]) => apply_message(graph, m, n, v) || graph, start);

// The class def the payload carries for ArcTranscription.
const classes = {
  NList: { children: ["N"] },
  SegmentList: { children: ["Arc", "Text", "Speaker"] },
  SectionList: { children: ["Arc", "Name"] },
};

describe("new_group", () => {
  // The group string is the wire format: the server splits it on "," and ":"
  // and logs the iids as the tree's new nodes. It has to come out exactly as
  // work/other.js's addf used to emit it.
  test("the list item, then its children in class-def order", () => {
    expect(new_group("SegmentList", classes, 4).value).toBe(
      "5:SegmentListItem,6:Arc,7:Text,8:Speaker",
    );
    expect(new_group("NList", classes, 0).value).toBe("1:NListItem,2:N");
    expect(new_group("SectionList", classes, 16).value).toBe("17:SectionListItem,18:Arc,19:Name");
  });

  test("it reports where the counter got to", () => {
    expect(new_group("SegmentList", classes, 4).last_iid).toBe(8);
  });

  test("iids carry on from there, never reused", () => {
    const first = new_group("NList", classes, 0);
    const second = new_group("NList", classes, first.last_iid);
    const third = new_group("SegmentList", classes, second.last_iid);
    expect([first.value, second.value, third.value]).toEqual([
      "1:NListItem,2:N",
      "3:NListItem,4:N",
      "5:SegmentListItem,6:Arc,7:Text,8:Speaker",
    ]);
  });

  test("a list the class def doesn't describe is just the item", () => {
    expect(new_group("MysteryList", classes, 0).value).toBe("1:MysteryListItem");
  });

  // What the tool actually does to make one segment: two anchors, then the
  // span. The iids in the messages have to line up with the graph it builds.
  test("the groups a segment is made of, then applied, describe that segment", () => {
    let last = 0;
    const messages = [];
    for (const list of ["NList", "NList", "SegmentList"]) {
      const group = new_group(list, classes, last);
      last = group.last_iid;
      messages.push(["add", "0", { value: group.value }]);
    }
    const graph = play(messages);
    expect(graph.nodes.map((n) => n.iid)).toEqual([1, 3]);
    expect(graph.arcs).toEqual([
      { iid: 5, name: "SegmentListItem", arc_node_iid: 6, beg_iid: null, end_iid: null },
    ]);
    expect(graph.labels.map((l) => l.name)).toEqual(["Text", "Speaker"]);
  });
});

describe("apply_message", () => {
  test("an add makes an anchor when the group has an N", () => {
    expect(apply_message(empty(), "add", "0", { value: "1:NListItem,2:N" })).toEqual({
      nodes: [{ iid: 1, n_iid: 2, docid: null, time: null }],
      arcs: [],
      labels: [],
    });
  });

  test("any other add makes a span with its labels, all empty", () => {
    expect(apply_message(empty(), "add", "0", { value: "5:SegmentListItem,6:Arc,7:Text,8:Speaker" })).toEqual({
      nodes: [],
      arcs: [{ iid: 5, name: "SegmentListItem", arc_node_iid: 6, beg_iid: null, end_iid: null }],
      labels: [
        { iid: 7, arc_iid: 5, name: "Text", value: "" },
        { iid: 8, arc_iid: 5, name: "Speaker", value: "" },
      ],
    });
  });

  test("a change to an N places the anchor in time", () => {
    const graph = play(one_segment.slice(0, 2));
    expect(graph.nodes).toEqual([{ iid: 1, n_iid: 2, docid: "a.wav", time: 0.5 }]);
  });

  test("a change to an Arc names the anchors it runs between", () => {
    const graph = play(one_segment);
    expect(graph.arcs).toEqual([{ iid: 5, name: "SegmentListItem", arc_node_iid: 6, beg_iid: 1, end_iid: 3 }]);
  });

  test("a change to anything else is a label", () => {
    const graph = play(one_segment);
    expect(graph.labels).toEqual([
      { iid: 7, arc_iid: 5, name: "Text", value: "some words" },
      { iid: 8, arc_iid: 5, name: "Speaker", value: "alice" },
    ]);
  });

  test("the whole stream derives to the segment the annotator made", () => {
    expect(graph_segments(play(one_segment))).toEqual([
      { iid: 5, arc_node_iid: 6, beg: 0.5, end: 2.0, text: "some words", speaker: "alice", label: "" },
    ]);
  });

  test("deleting a span takes its labels with it", () => {
    const graph = apply_message(play(one_segment), "delete", 5, null);
    expect(graph.arcs).toEqual([]);
    expect(graph.labels).toEqual([]);
    expect(graph.nodes.length).toBe(2); // the anchors are their own groups
  });

  test("deleting an anchor leaves the span without that time", () => {
    const graph = apply_message(play(one_segment), "delete", 1, null);
    expect(graph_segments(graph)).toEqual([]); // no beg: not a row until it has one
    expect(graph.arcs[0].beg_iid).toBe(1);
  });

  test("messages that aren't about the tree change nothing", () => {
    for (const m of ["done", "broken", "skip", "new"]) {
      expect(apply_message(play(one_segment), m, "0", "comment")).toBeNull();
    }
  });

  test("a change to an iid the graph doesn't have changes nothing", () => {
    expect(apply_message(play(one_segment), "change", 99, { value: "x" })).toBeNull();
  });

  test("rows stay in iid order however they arrive", () => {
    const graph = play([
      ["add", "0", { value: "9:NListItem,10:N" }],
      ["add", "0", { value: "1:NListItem,2:N" }],
      ["add", "0", { value: "20:SegmentListItem,21:Arc,22:Text" }],
      ["add", "0", { value: "5:SegmentListItem,6:Arc,7:Text" }],
    ]);
    expect(graph.nodes.map((n) => n.iid)).toEqual([1, 9]);
    expect(graph.arcs.map((a) => a.iid)).toEqual([5, 20]);
    expect(graph.labels.map((l) => l.arc_iid)).toEqual([5, 20]);
  });
});

// The applier and the fold are two routes to the same rows, and the whole
// arrangement rests on them agreeing. Build the node layer the messages would
// have built and fold it, then compare.
describe("applying agrees with folding", () => {
  const node_layer = (nodes: any[]) =>
    new Map(nodes.map((n) => [n.iid, { ...n, node_value: writable(n.value || { value: "" }) }]));

  // What work/other.js's addf + changef leave in ldc.nodes for one_segment.
  const after_one_segment = node_layer([
    { iid: 1, name: "NListItem", parent_iid: null, level: 2 },
    { iid: 2, name: "N", parent_iid: 1, level: 3, value: { docid: "a.wav", beg: 0.5, type: "real" } },
    { iid: 3, name: "NListItem", parent_iid: null, level: 2 },
    { iid: 4, name: "N", parent_iid: 3, level: 3, value: { docid: "a.wav", beg: 2.0, type: "real" } },
    { iid: 5, name: "SegmentListItem", parent_iid: null, level: 2 },
    { iid: 6, name: "Arc", parent_iid: 5, level: 3, value: { beg: 1, end: 3 } },
    { iid: 7, name: "Text", parent_iid: 5, level: 3, value: { value: "some words" } },
    { iid: 8, name: "Speaker", parent_iid: 5, level: 3, value: { value: "alice" } },
  ]);

  test("the same messages give the same rows either way", () => {
    expect(graph_difference(play(one_segment), graph_from_nodes(after_one_segment))).toBeNull();
  });

  test("and after a delete", () => {
    const applied = apply_message(play(one_segment), "delete", 5, null);
    const nodes = new Map(after_one_segment);
    for (const iid of [5, 6, 7, 8]) nodes.delete(iid);
    expect(graph_difference(applied, graph_from_nodes(nodes))).toBeNull();
  });
});

describe("graph_difference", () => {
  test("a label never set reads the same empty either way", () => {
    const applied = { nodes: [], arcs: [], labels: [{ iid: 7, arc_iid: 5, name: "Text", value: "" }] };
    const folded = { nodes: [], arcs: [], labels: [{ iid: 7, arc_iid: 5, name: "Text", value: null }] };
    expect(graph_difference(applied, folded)).toBeNull();
  });

  test("a time as a string and as a number are the same time", () => {
    const applied = { nodes: [{ iid: 1, n_iid: 2, docid: "a.wav", time: "0.5" }], arcs: [], labels: [] };
    const folded = { nodes: [{ iid: 1, n_iid: 2, docid: "a.wav", time: 0.5 }], arcs: [], labels: [] };
    expect(graph_difference(applied, folded)).toBeNull();
  });

  test("a row only one side has is reported, with which side", () => {
    const applied = play(one_segment);
    const folded = apply_message(applied, "delete", 5, null);
    const difference = graph_difference(applied, folded);
    expect(difference).toContain("applied only: arc 5");
  });

  test("a value that differs is reported", () => {
    const applied = play(one_segment);
    const folded = apply_message(applied, "change", 7, { value: "something else" });
    expect(graph_difference(applied, folded)).toContain("Text=some words");
  });
});
