import { describe, expect, test } from "vitest";
import { apply_message, begin_batch, apply_batched, end_batch } from "./graph_write";

// The batched path exists only to be faster. Any difference in what it produces
// is a bug, so every test here is the same shape: run a sequence of messages
// through apply_message one at a time, run it through the batch, compare.
//
// That is also the only check worth having. The batch keeps indexes, tombstones
// deletes and defers the sort — three chances to disagree with the pure path,
// and none of them are visible from the outside until the transcript is wrong.
const EMPTY = { nodes: [], arcs: [], labels: [] };

type Msg = [string, unknown, unknown];

function pure(messages: Msg[], from = EMPTY) {
  let graph = from;
  for (const [m, n, v] of messages) {
    const next = apply_message(graph, m, n, v);
    if (next) graph = next;
  }
  return graph;
}

function batched(messages: Msg[], from = EMPTY) {
  const b = begin_batch(from);
  for (const [m, n, v] of messages) apply_batched(b, m, n, v);
  return end_batch(b) ?? from;
}

const segment = (base: number): Msg =>
  ["add", 0, { value: `${base}:SegmentListItem,${base + 1}:Arc,${base + 2}:Text,${base + 3}:Speaker` }];
const anchor = (base: number): Msg => ["add", 0, { value: `${base}:NListItem,${base + 1}:N` }];

describe("the batched path matches the pure one", () => {
  test("a single add", () => {
    const m: Msg[] = [ segment(1) ];
    expect(batched(m)).toEqual(pure(m));
  });

  test("an anchor add, which lands in nodes rather than arcs", () => {
    const m: Msg[] = [ anchor(1) ];
    expect(batched(m)).toEqual(pure(m));
  });

  test("adds then changes to their labels", () => {
    const m: Msg[] = [
      segment(1),
      ["change", 3, { value: "hello" }],
      ["change", 4, { value: "alice" }],
    ];
    expect(batched(m)).toEqual(pure(m));
  });

  test("a change to an arc's times", () => {
    const m: Msg[] = [ segment(1), ["change", 2, { beg: 1.5, end: 3.0 }] ];
    expect(batched(m)).toEqual(pure(m));
  });

  test("a change to an anchor's docid and time", () => {
    const m: Msg[] = [ anchor(1), ["change", 2, { docid: "a.wav", beg: 0.5 }] ];
    expect(batched(m)).toEqual(pure(m));
  });

  // Appends go on the end and the sort happens once, so out-of-order adds are
  // where a deferred sort would show.
  test("adds out of iid order still come back sorted", () => {
    const m: Msg[] = [ segment(9), segment(1), segment(5) ];
    expect(batched(m)).toEqual(pure(m));
  });

  test("a delete takes the span's labels with it", () => {
    const m: Msg[] = [ segment(1), segment(5), ["delete", 1, null] ];
    expect(batched(m)).toEqual(pure(m));
  });

  test("deleting an anchor", () => {
    const m: Msg[] = [ anchor(1), segment(5), ["delete", 1, null] ];
    expect(batched(m)).toEqual(pure(m));
  });

  // Tombstones mean a deleted row is still in the array mid-batch; a later
  // message must not find it.
  test("a change to something already deleted in the same batch", () => {
    const m: Msg[] = [ segment(1), ["delete", 1, null], ["change", 3, { value: "ghost" }] ];
    expect(batched(m)).toEqual(pure(m));
  });

  test("deleting twice", () => {
    const m: Msg[] = [ segment(1), ["delete", 1, null], ["delete", 1, null] ];
    expect(batched(m)).toEqual(pure(m));
  });

  test("two changes to one label, last wins", () => {
    const m: Msg[] = [ segment(1), ["change", 3, { value: "first" }], ["change", 3, { value: "second" }] ];
    expect(batched(m)).toEqual(pure(m));
  });

  test("a message naming nothing changes nothing", () => {
    const m: Msg[] = [ segment(1), ["change", 999, { value: "nowhere" }] ];
    expect(batched(m)).toEqual(pure(m));
  });

  test("messages that don't touch the rows at all", () => {
    const m: Msg[] = [ segment(1), ["done", 1, null], ["broken", 1, null] ];
    expect(batched(m)).toEqual(pure(m));
  });

  // What a speaker replace looks like: many changes across many spans.
  test("a replace across 50 segments", () => {
    const m: Msg[] = [];
    for (let i = 0; i < 50; i++) m.push(segment(1 + i * 4));
    for (let i = 0; i < 50; i++) m.push(["change", 4 + i * 4, { value: "subject" }]);
    expect(batched(m)).toEqual(pure(m));
  });

  // And a delete-all: every list item, in one go.
  test("deleting 50 segments", () => {
    const m: Msg[] = [];
    for (let i = 0; i < 50; i++) m.push(segment(1 + i * 4));
    for (let i = 0; i < 50; i++) m.push(["delete", 1 + i * 4, null]);
    expect(batched(m)).toEqual(pure(m));
  });

  test("starting from a graph that already has rows", () => {
    const start = pure([ segment(1), segment(5), ["change", 3, { value: "kept" }] ]);
    const m: Msg[] = [ segment(9), ["change", 7, { value: "new" }], ["delete", 1, null] ];
    expect(batched(m, start)).toEqual(pure(m, start));
  });
});

describe("the batch leaves what it was given alone", () => {
  test("the graph passed to begin_batch is unchanged", () => {
    const start = pure([ segment(1), ["change", 3, { value: "original" }] ]);
    const snapshot = structuredClone(start);

    batched([ ["change", 3, { value: "altered" }], ["delete", 1, null] ], start);

    expect(start).toEqual(snapshot);
  });
});

describe("end_batch reports nothing happening", () => {
  test("no messages", () => {
    expect(end_batch(begin_batch(EMPTY))).toBe(null);
  });

  test("only messages that touch nothing", () => {
    const b = begin_batch(EMPTY);
    apply_batched(b, "done", 1, null);
    apply_batched(b, "change", 42, { value: "nowhere" });
    expect(end_batch(b)).toBe(null);
  });
});
