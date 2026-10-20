import { describe, expect, test } from "vitest";
import {
  lanes_for, resolve_block, extent, lane_spans, lane_depth, in_view, pack,
  zoom_at, pan_by, clamp_view, neighbourhood, ticks, format_time,
  document_key, group_by_document, NO_DOCID,
  thumb_geometry, view_from_thumb, zoom_slider_value, view_from_zoom_slider,
  MIN_THUMB, MIN_WINDOW, document_labels
} from "./task_graph_layout";

// One kit's rows, exactly as /projects/:id/tasks/:id/graph.json sends them —
// GraphNode#to_row, GraphArc#to_row(times) and GraphLabel#to_row.
//
//   anchors 10 12 14 at 0, 1.5, 4
//   a segment 20 over 10→12 with Text and Speaker
//   a segment 30 over 12→14 with Text and Speaker
//   a section 40 over 10→14 with a Name
const kit = {
  kit_id: 1,
  uid: "kit-a",
  docid: "a.wav",
  nodes: [
    { iid: 10, n_iid: 11, docid: "a.wav", time: 0 },
    { iid: 12, n_iid: 13, docid: "a.wav", time: 1.5 },
    { iid: 14, n_iid: 15, docid: "a.wav", time: 4 },
  ],
  arcs: [
    { iid: 20, name: "SegmentListItem", arc_node_iid: 21, beg_iid: 10, end_iid: 12, beg: 0, end: 1.5 },
    { iid: 30, name: "SegmentListItem", arc_node_iid: 31, beg_iid: 12, end_iid: 14, beg: 1.5, end: 4 },
    { iid: 40, name: "SectionListItem", arc_node_iid: 41, beg_iid: 10, end_iid: 14, beg: 0, end: 4 },
  ],
  labels: [
    { iid: 22, arc_iid: 20, name: "Text", value: "hello" },
    { iid: 23, arc_iid: 20, name: "Speaker", value: "alice" },
    { iid: 32, arc_iid: 30, name: "Text", value: "how are you" },
    { iid: 33, arc_iid: 30, name: "Speaker", value: "bob" },
    { iid: 42, arc_iid: 40, name: "Name", value: "intro" },
  ],
};

const resolved = resolve_block(kit);

describe("lanes_for", () => {
  test("a lane per arc name and label name, in the order they appear", () => {
    expect(lanes_for([resolved]).map((l) => l.key)).toEqual([
      "SegmentListItem Text",
      "SegmentListItem Speaker",
      "SectionListItem Name",
    ]);
  });

  test("a group nobody has taught it about gets a lane anyway", () => {
    // The whole bargain of the graph tables: the client owns the vocabulary.
    const invented = resolve_block({
      ...kit,
      arcs: [ ...kit.arcs, { iid: 50, name: "CommentListItem", arc_node_iid: 51, beg_iid: 10, end_iid: 12, beg: 0, end: 1.5 } ],
      labels: [ ...kit.labels, { iid: 52, arc_iid: 50, name: "Comment", value: "noisy" } ],
    });
    expect(lanes_for([invented]).map((l) => l.key)).toContain("CommentListItem Comment");
  });

  test("an arc carrying no labels still gets one", () => {
    const bare = resolve_block({
      nodes: kit.nodes,
      arcs: [ { iid: 60, name: "TurnListItem", arc_node_iid: 61, beg_iid: 10, end_iid: 14, beg: 0, end: 4 } ],
      labels: [],
    });
    expect(lanes_for([bare])).toEqual([ { key: "TurnListItem", arc_name: "TurnListItem", label_name: null } ]);
  });

  test("lanes are the union across kits, each named once", () => {
    const other = resolve_block({ ...kit, kit_id: 2, labels: [ { iid: 22, arc_iid: 20, name: "Text", value: "x" } ] });
    expect(lanes_for([resolved, other]).filter((l) => l.key === "SegmentListItem Text")).toHaveLength(1);
  });
});

describe("resolve_block", () => {
  test("labels are attached to the span they hang off", () => {
    const arc = resolved.arcs.find((a) => a.iid === 20);
    expect(arc.label_values).toEqual({ Text: "hello", Speaker: "alice" });
    expect(arc.labels.map((l) => l.iid)).toEqual([22, 23]);
  });

  test("a span whose anchor is gone is marked, not dropped", () => {
    // graph_summary calls these dangling arcs; they should be visible as a
    // problem rather than quietly missing from the drawing.
    const broken = resolve_block({
      nodes: kit.nodes,
      arcs: [ { iid: 70, name: "SegmentListItem", arc_node_iid: 71, beg_iid: 10, end_iid: 99, beg: 0, end: null } ],
      labels: [],
    });
    expect(broken.arcs[0].dangling).toBe(true);
  });

  test("the anchor's time wins over the arc's copy of it", () => {
    // The anchors are the identity; beg/end on the arc are the convenience.
    const disagreeing = resolve_block({
      nodes: [ { iid: 10, time: 2 }, { iid: 12, time: 3 } ],
      arcs: [ { iid: 20, name: "SegmentListItem", beg_iid: 10, end_iid: 12, beg: 0, end: 99 } ],
      labels: [],
    });
    expect(disagreeing.arcs[0]).toMatchObject({ beg: 2, end: 3 });
  });
});

describe("extent", () => {
  test("spans every anchor of every kit", () => {
    const later = resolve_block({ nodes: [ { iid: 80, time: 9 } ], arcs: [], labels: [] });
    expect(extent([resolved, later])).toEqual({ beg: 0, end: 9 });
  });

  test("a kit with one anchor still has a width to draw in", () => {
    expect(extent([resolve_block({ nodes: [ { iid: 1, time: 5 } ], arcs: [], labels: [] })]))
      .toEqual({ beg: 5, end: 6 });
  });

  test("nothing annotated is a unit window rather than a division by zero", () => {
    expect(extent([])).toEqual({ beg: 0, end: 1 });
  });
});

describe("lane_spans", () => {
  const lanes = lanes_for([resolved]);
  const text = lanes.find((l) => l.key === "SegmentListItem Text");
  const name = lanes.find((l) => l.key === "SectionListItem Name");

  test("takes only the arcs of its own name", () => {
    expect(lane_spans(resolved, text).map((s) => s.iid)).toEqual([20, 30]);
    expect(lane_spans(resolved, name).map((s) => s.iid)).toEqual([40]);
  });

  test("skips an arc of the right name that lacks this lane's label", () => {
    const partial = resolve_block({
      ...kit,
      labels: kit.labels.filter((l) => !(l.arc_iid === 30 && l.name === "Speaker")),
    });
    const speaker = lanes.find((l) => l.key === "SegmentListItem Speaker");
    expect(lane_spans(partial, speaker).map((s) => s.iid)).toEqual([20]);
  });

  test("a dangling span has no place on the axis, so it isn't placed", () => {
    const broken = resolve_block({
      nodes: kit.nodes,
      arcs: [ ...kit.arcs, { iid: 70, name: "SegmentListItem", beg_iid: 10, end_iid: 99, beg: 0, end: null } ],
      labels: [ ...kit.labels, { iid: 72, arc_iid: 70, name: "Text", value: "lost" } ],
    });
    expect(lane_spans(broken, text).map((s) => s.iid)).toEqual([20, 30]);
  });
});

describe("pack", () => {
  test("spans that don't overlap share a row", () => {
    expect(pack([
      { iid: 1, beg: 0, end: 1 },
      { iid: 2, beg: 1, end: 2 },
    ]).map((s) => s.row)).toEqual([0, 0]);
  });

  test("overlapping spans stack instead of hiding each other", () => {
    // Comments overlap by nature; a lane drawing one on top of another would
    // be lying about what's in the table.
    expect(pack([
      { iid: 1, beg: 0, end: 3 },
      { iid: 2, beg: 1, end: 4 },
      { iid: 3, beg: 2, end: 5 },
    ]).map((s) => s.row)).toEqual([0, 1, 2]);
  });

  test("a freed row is reused", () => {
    expect(pack([
      { iid: 1, beg: 0, end: 3 },
      { iid: 2, beg: 1, end: 2 },
      { iid: 3, beg: 4, end: 5 },
    ]).map((s) => [s.iid, s.row])).toEqual([[1, 0], [2, 1], [3, 0]]);
  });

  test("rows are assigned over the whole recording, not the window", () => {
    // Packing per window would make a span jump rows as the one it overlapped
    // scrolled off the left edge; the depth is what the lane's height uses.
    const spans = pack([ { iid: 1, beg: 0, end: 3 }, { iid: 2, beg: 1, end: 4 } ]);
    expect(lane_depth(spans)).toBe(2);
    expect(in_view(spans, { beg: 3.5, end: 4 }).map((s) => s.row)).toEqual([1]);
  });
});

describe("in_view", () => {
  const spans = pack([
    { iid: 1, beg: 0, end: 1 },
    { iid: 2, beg: 5, end: 6 },
    { iid: 3, beg: 10, end: 11 },
  ]);

  test("keeps what touches the window and drops the rest", () => {
    expect(in_view(spans, { beg: 4, end: 7 }).map((s) => s.iid)).toEqual([2]);
  });

  test("a span straddling the window counts as in it", () => {
    expect(in_view(pack([ { iid: 1, beg: 0, end: 100 } ]), { beg: 40, end: 50 })).toHaveLength(1);
  });

  test("touching the edge counts", () => {
    expect(in_view(spans, { beg: 1, end: 5 }).map((s) => s.iid)).toEqual([1, 2]);
  });
});

describe("zoom and pan", () => {
  const limit = { beg: 0, end: 100 };

  test("zooming keeps the time under the pointer where it is", () => {
    const view = zoom_at({ beg: 0, end: 100 }, 2, 25, limit);
    expect(view.end - view.beg).toBeCloseTo(50);
    expect((25 - view.beg) / (view.end - view.beg)).toBeCloseTo(0.25);
  });

  test("zooming out stops at the whole task", () => {
    expect(zoom_at({ beg: 40, end: 60 }, 0.001, 50, limit)).toEqual(limit);
  });

  test("zooming in stops at a millisecond", () => {
    const view = zoom_at({ beg: 0, end: 100 }, 1e9, 50, limit);
    expect(view.end - view.beg).toBeCloseTo(0.001);
  });

  test("panning off the end parks at the end and keeps its width", () => {
    const view = pan_by({ beg: 90, end: 100 }, 50, limit);
    expect(view).toEqual({ beg: 90, end: 100 });
  });

  test("panning off the front parks at the front", () => {
    expect(pan_by({ beg: 10, end: 20 }, -50, limit)).toEqual({ beg: 0, end: 10 });
  });

  test("a window wider than the task is the task", () => {
    expect(clamp_view({ beg: -50, end: 200 }, limit)).toEqual(limit);
  });
});

describe("neighbourhood", () => {
  test("the anchors at each end, and every span sharing one", () => {
    // Segment 20 ends at anchor 12, where segment 30 begins, and both ends sit
    // under section 40 — the sharing a timeline can't show.
    const arc = resolved.arcs.find((a) => a.iid === 20);
    const n = neighbourhood(resolved, arc);
    expect(n.anchors.map((a) => a.iid)).toEqual([10, 12]);
    expect(n.neighbours.map((a) => a.iid)).toEqual([30, 40]);
  });

  test("a span abutting at an equal time but a different anchor isn't a neighbour", () => {
    // This is the distinction the inspector exists for: same picture on the
    // timeline, different graph.
    const abutting = resolve_block({
      nodes: [ ...kit.nodes, { iid: 16, time: 1.5 } ],
      arcs: [
        kit.arcs[0],
        { iid: 30, name: "SegmentListItem", beg_iid: 16, end_iid: 14, beg: 1.5, end: 4 },
      ],
      labels: [],
    });
    const arc = abutting.arcs.find((a) => a.iid === 20);
    expect(neighbourhood(abutting, arc).neighbours).toEqual([]);
  });
});

describe("ticks", () => {
  test("round times, roughly as many as asked for", () => {
    expect(ticks({ beg: 0, end: 10 }, 10)).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  });

  test("the step grows with the window", () => {
    expect(ticks({ beg: 0, end: 1000 }, 10)).toEqual([0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]);
  });

  test("zoomed in far enough, the step is sub-second and stays round", () => {
    expect(ticks({ beg: 1, end: 1.5 }, 10))
      .toEqual([1, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.35, 1.4, 1.45, 1.5]);
  });

  test("the step is one of 1, 2, 5 times a power of ten, never a fraction of one", () => {
    // The labels are read off at a glance; a tick every 0.037s would not be.
    for (const width of [0.05, 0.3, 7, 43, 900]) {
      const t = ticks({ beg: 0, end: width }, 10);
      if (t.length < 2) continue;
      const step = t[1] - t[0];
      const magnitude = Math.pow(10, Math.floor(Math.log10(step)));
      expect([1, 2, 5, 10]).toContain(Math.round(step / magnitude));
    }
  });

  test("a window with no width has no ticks rather than an infinite loop", () => {
    expect(ticks({ beg: 5, end: 5 })).toEqual([]);
  });
});

describe("format_time", () => {
  test("seconds under a minute, trimmed", () => {
    expect(format_time(1.5)).toBe("1.5s");
    expect(format_time(0)).toBe("0s");
  });

  test("minutes and seconds beyond one", () => {
    expect(format_time(95.25)).toBe("1:35.250");
  });

  test("nothing to say about a missing time", () => {
    expect(format_time(null)).toBe("");
    expect(format_time(undefined)).toBe("");
  });
});

describe("document_key", () => {
  test("the kit's own docid when it has one", () => {
    expect(document_key(resolved)).toBe("a.wav");
  });

  test("falls back to what the anchors say", () => {
    // A kit with no source_uid still wrote a docid on every time it recorded.
    expect(document_key(resolve_block({ ...kit, docid: null }))).toBe("a.wav");
  });

  test("and says so when there is nothing to go on", () => {
    expect(document_key(resolve_block({ nodes: [ { iid: 1, time: 0 } ], arcs: [], labels: [] })))
      .toBe(NO_DOCID);
  });
});

describe("group_by_document", () => {
  // Two kits over one recording — a second pass, or a QC check.
  const second = resolve_block({
    ...kit,
    kit_id: 2,
    uid: "kit-b",
    arcs: [ { iid: 20, name: "SegmentListItem", arc_node_iid: 21, beg_iid: 10, end_iid: 12, beg: 0, end: 1.5 } ],
    labels: [ { iid: 22, arc_iid: 20, name: "Text", value: "hello again" } ],
  });
  const other_doc = resolve_block({ ...kit, kit_id: 3, docid: "b.wav" });

  test("kits over one recording become one document", () => {
    const docs = group_by_document([resolved, second, other_doc]);
    expect(docs.map((d) => d.docid)).toEqual(["a.wav", "b.wav"]);
    expect(docs[0].kits.map((k) => k.kit_id)).toEqual([1, 2]);
  });

  test("its spans are every kit's, on one set of lanes", () => {
    // The point of the grouping: one document is drawn once, not once per kit
    // with a screenful of nothing between them.
    const doc = group_by_document([resolved, second])[0];
    expect(doc.arcs).toHaveLength(4);
    const lanes = lanes_for([doc]);
    const text = lanes.find((l) => l.key === "SegmentListItem Text");
    expect(lane_spans(doc, text).map((s) => s.kit_id)).toEqual([1, 2, 1]);
  });

  test("a span merged into a document still names its kit", () => {
    // Its iid can't: iids are unique within a tree, not across them. Both of
    // these kits have a span 20, and they are different spans.
    const doc = group_by_document([resolved, second])[0];
    const twenties = doc.arcs.filter((a) => a.iid === 20);
    expect(twenties.map((a) => a.kit_id)).toEqual([1, 2]);
  });

  test("kits sharing a document do not share anchors", () => {
    // The merge is a drawing. Each kit keeps its own tree, so a span's
    // neighbours are the ones inside its own kit — never the other kit's,
    // however exactly the times line up.
    const doc = group_by_document([resolved, second])[0];
    const arc = second.arcs.find((a) => a.iid === 20);
    expect(neighbourhood(second, arc).neighbours).toEqual([]);
    // ...even though the merged document has spans on the very same times.
    expect(doc.arcs.filter((a) => a.beg === 0 && a.end === 1.5)).toHaveLength(2);
  });

  test("packing settles a tie between two kits' identical iids", () => {
    const doc = group_by_document([resolved, second])[0];
    // Both kits have a SegmentListItem 20 starting at 0.
    const rows = pack(doc.arcs.filter((a) => a.beg === 0 && a.name === "SegmentListItem"));
    expect(rows.map((r) => [r.kit_id, r.row])).toEqual([[1, 0], [2, 1]]);
  });

  test("kits with no docid gather under one heading rather than scattering", () => {
    const bare = (id) => resolve_block({ kit_id: id, docid: null, nodes: [], arcs: [], labels: [] });
    expect(group_by_document([bare(7), bare(8)]).map((d) => [d.docid, d.kits.length]))
      .toEqual([[NO_DOCID, 2]]);
  });

  test("documents come out in the order their first kit did", () => {
    const docs = group_by_document([other_doc, resolved, second]);
    expect(docs.map((d) => d.docid)).toEqual(["b.wav", "a.wav"]);
  });
});

describe("thumb_geometry", () => {
  const limit = { beg: 0, end: 100 };
  const TRACK = 400;

  test("the thumb covers the share of the task on screen", () => {
    expect(thumb_geometry({ beg: 0, end: 25 }, limit, TRACK).width).toBe(100);
    expect(thumb_geometry({ beg: 0, end: 50 }, limit, TRACK).width).toBe(200);
  });

  test("the whole task fills the track, and there is nowhere to drag it", () => {
    const g = thumb_geometry({ beg: 0, end: 100 }, limit, TRACK);
    expect(g).toMatchObject({ left: 0, width: TRACK, travel: 0, movable: false });
  });

  test("it sits where the window sits", () => {
    expect(thumb_geometry({ beg: 0, end: 25 }, limit, TRACK).left).toBe(0);
    expect(thumb_geometry({ beg: 75, end: 100 }, limit, TRACK).left).toBe(300); // flush right
    expect(thumb_geometry({ beg: 37.5, end: 62.5 }, limit, TRACK).left).toBe(150);
  });

  test("zoomed far in it stops shrinking, or there would be nothing to grab", () => {
    const g = thumb_geometry({ beg: 0, end: 0.01 }, limit, TRACK);
    expect(g.width).toBe(MIN_THUMB);
  });

  test("…and the travel shrinks with it, so the end is still reachable", () => {
    // The floor makes the thumb wider than the share it stands for. If travel
    // stayed at track - proportional_width the thumb would run off the end
    // before the window reached it.
    const view = { beg: 99.99, end: 100 };
    const g = thumb_geometry(view, limit, TRACK);
    expect(g.travel).toBe(TRACK - MIN_THUMB);
    expect(g.left).toBeCloseTo(g.travel); // flush against the right
  });

  test("a track with no width doesn't produce NaN", () => {
    expect(thumb_geometry({ beg: 0, end: 10 }, limit, 0)).toMatchObject({ left: 0, movable: false });
  });

  test("a task with no duration doesn't divide by zero", () => {
    expect(thumb_geometry({ beg: 5, end: 5 }, { beg: 5, end: 5 }, TRACK).movable).toBe(false);
  });
});

describe("view_from_thumb", () => {
  const limit = { beg: 0, end: 100 };
  const TRACK = 400;
  const view = { beg: 0, end: 25 };

  test("dragging to the far end shows the end of the task", () => {
    expect(view_from_thumb(TRACK, view, limit, TRACK)).toEqual({ beg: 75, end: 100 });
  });

  test("dragging back past the start stops at the start", () => {
    expect(view_from_thumb(-500, { beg: 50, end: 75 }, limit, TRACK)).toEqual({ beg: 0, end: 25 });
  });

  test("the window keeps its width wherever it is dragged", () => {
    for (const at of [0, 50, 137, 299, 400]) {
      const moved = view_from_thumb(at, view, limit, TRACK);
      expect(moved.end - moved.beg).toBeCloseTo(25);
    }
  });

  test("it undoes thumb_geometry — drag to where the thumb is and nothing moves", () => {
    for (const start of [{ beg: 0, end: 25 }, { beg: 30, end: 55 }, { beg: 75, end: 100 }]) {
      const { left } = thumb_geometry(start, limit, TRACK);
      expect(view_from_thumb(left, start, limit, TRACK).beg).toBeCloseTo(start.beg);
    }
  });

  test("round-trips at the floor too, where the thumb is wider than its share", () => {
    const start = { beg: 60, end: 60.01 };
    const { left } = thumb_geometry(start, limit, TRACK);
    expect(view_from_thumb(left, start, limit, TRACK).beg).toBeCloseTo(start.beg);
  });

  test("with the whole task shown there is nowhere to drag to", () => {
    expect(view_from_thumb(300, { beg: 0, end: 100 }, limit, TRACK)).toEqual({ beg: 0, end: 100 });
  });
});

describe("zoom_slider_value", () => {
  const limit = { beg: 0, end: 100 };

  test("the whole task is one end, the floor is the other", () => {
    expect(zoom_slider_value({ beg: 0, end: 100 }, limit)).toBe(0);
    expect(zoom_slider_value({ beg: 0, end: MIN_WINDOW }, limit)).toBeCloseTo(1);
  });

  test("it is logarithmic, so the middle is the geometric mean", () => {
    // Linear, half the bar would be spent between 100s and 50s and the last
    // pixel would cross three orders of magnitude.
    const middle = Math.sqrt(100 * MIN_WINDOW);
    expect(zoom_slider_value({ beg: 0, end: middle }, limit)).toBeCloseTo(0.5);
  });

  test("a window outside the range is pinned to its end", () => {
    expect(zoom_slider_value({ beg: 0, end: 500 }, limit)).toBe(0);
    expect(zoom_slider_value({ beg: 0, end: 0.0001 }, limit)).toBeCloseTo(1);
  });

  test("a task shorter than the floor has no zoom to offer", () => {
    expect(zoom_slider_value({ beg: 0, end: 0.05 }, { beg: 0, end: 0.05 })).toBe(0);
  });
});

describe("view_from_zoom_slider", () => {
  const limit = { beg: 0, end: 100 };

  test("0 is the whole task", () => {
    expect(view_from_zoom_slider(0, { beg: 40, end: 60 }, limit)).toEqual({ beg: 0, end: 100 });
  });

  test("1 is the narrowest the bar goes", () => {
    const v = view_from_zoom_slider(1, { beg: 40, end: 60 }, limit);
    expect(v.end - v.beg).toBeCloseTo(MIN_WINDOW);
  });

  test("zooming holds the centre, so it doesn't walk sideways", () => {
    const v = view_from_zoom_slider(0.5, { beg: 40, end: 60 }, limit);
    expect((v.beg + v.end) / 2).toBeCloseTo(50);
  });

  test("near an edge it stays inside the task rather than holding the centre", () => {
    const v = view_from_zoom_slider(0.2, { beg: 0, end: 5 }, limit);
    expect(v.beg).toBeGreaterThanOrEqual(0);
    expect(v.end).toBeLessThanOrEqual(100);
  });

  test("it round-trips with zoom_slider_value", () => {
    for (const at of [0, 0.25, 0.5, 0.75, 1]) {
      const v = view_from_zoom_slider(at, { beg: 40, end: 60 }, limit);
      expect(zoom_slider_value(v, limit)).toBeCloseTo(at, 5);
    }
  });

  test("a value off the ends is clamped, not extrapolated", () => {
    expect(view_from_zoom_slider(-3, { beg: 40, end: 60 }, limit)).toEqual({ beg: 0, end: 100 });
    const v = view_from_zoom_slider(9, { beg: 40, end: 60 }, limit);
    expect(v.end - v.beg).toBeCloseTo(MIN_WINDOW);
  });
});

describe("document_labels", () => {
  const name = (docids: string[], of: string) => document_labels(docids).get(of);

  test("a docid is called by the end of its path", () => {
    expect(name(["s3://my-bucket/recordings/0703D8C6_passage_reading.wav"],
                "s3://my-bucket/recordings/0703D8C6_passage_reading.wav"))
      .toBe("0703D8C6_passage_reading.wav");
  });

  test("a URL loses its scheme and host too", () => {
    expect(name(["https://ldcresearch.s3.us-east-1.amazonaws.com/CarrieFisher.wav"],
                "https://ldcresearch.s3.us-east-1.amazonaws.com/CarrieFisher.wav"))
      .toBe("CarrieFisher.wav");
  });

  test("the extension stays, because it is sometimes the whole difference", () => {
    // Two kits over one recording, one the audio and one a transcript of it.
    const docids = [ "s3://c/CarrieFisher10s.wav", "s3://c/CarrieFisher10s.json" ];
    expect(docids.map((d) => name(docids, d))).toEqual([
      "CarrieFisher10s.wav", "CarrieFisher10s.json"
    ]);
  });

  test("a query string is dropped — a signed URL is mostly signature", () => {
    const url = "https://x/take1.wav?X-Amz-Signature=abc&X-Amz-Expires=900";
    expect(name([url], url)).toBe("take1.wav");
  });

  test("names that would collide take another segment, and only those", () => {
    // Two rows reading "take1.wav" would be a picker you can't pick with.
    const docids = [ "s3://c/a/take1.wav", "s3://c/b/take1.wav", "s3://c/other.wav" ];
    expect(docids.map((d) => name(docids, d))).toEqual([
      "a/take1.wav", "b/take1.wav", "other.wav"
    ]);
  });

  test("it keeps going until they are distinct", () => {
    const docids = [ "s3://c/one/take/1.wav", "s3://c/two/take/1.wav" ];
    expect(docids.map((d) => name(docids, d))).toEqual([
      "one/take/1.wav", "two/take/1.wav"
    ]);
  });

  test("two docids that really are the same keep the name rather than looping", () => {
    const docids = [ "take1.wav", "take1.wav" ];
    expect(docids.map((d) => name(docids, d))).toEqual([ "take1.wav", "take1.wav" ]);
  });

  test("a docid with no path at all is itself", () => {
    expect(name([ "(no docid)" ], "(no docid)")).toBe("(no docid)");
    expect(name([ "plain_name" ], "plain_name")).toBe("plain_name");
  });

  test("a trailing slash doesn't produce an empty name", () => {
    expect(name([ "s3://c/folder/" ], "s3://c/folder/")).toBe("folder");
  });

  test("every document gets a name, and none is empty", () => {
    const docids = [ "s3://c/a.wav", "https://x/b.wav", "(no docid)", "c.wav" ];
    const labels = document_labels(docids);
    expect(labels.size).toBe(docids.length);
    for (const value of labels.values()) expect(value.length).toBeGreaterThan(0);
  });
});
