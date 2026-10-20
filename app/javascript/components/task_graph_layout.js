// Turning a task's graph rows into something drawable.
//
// The rows arrive exactly as graph_nodes / graph_arcs / graph_labels hold them
// — anchors with times, spans naming two anchors, labels hanging off spans —
// and this file works out what lanes exist, where each span sits on the time
// axis, and which spans are worth emitting for the window currently in view.
// No DOM, no svelte: task_graph.svelte draws whatever comes out of here, and
// the tests drive it directly.
//
// Nothing here knows the vocabulary. Lanes are discovered from the `name`
// columns, so a group the client invents — a comment span, a topic span —
// gets a lane the first time one is annotated, with no change on either side.
// That is the same bargain the rest of the graph tables make (ARCHITECTURE.md,
// "Two projections").

// One lane per (arc name, label name) pair present in the data: a segment's
// Text and its Speaker are read against each other, so they get a row each.
// An arc name that carries no labels at all still gets a lane — the spans are
// worth seeing even when nothing is said about them.
//
// Order is first appearance, scanning kits in the order the server sent them.
// That's deterministic and it reflects the task rather than a list held here.
export function lanes_for(blocks) {
  const lanes = [];
  const seen = new Set();
  const add = (arc_name, label_name) => {
    const key = label_name === null ? arc_name : `${arc_name} ${label_name}`;
    if (seen.has(key)) return;
    seen.add(key);
    lanes.push({ key, arc_name, label_name });
  };

  // Read off each arc's own labels, which resolve_block has already attached.
  // Looking them up by arc_iid instead would break on a document holding two
  // kits: an iid is unique within a tree, not across them.
  for (const block of blocks) {
    for (const arc of block.arcs ?? []) {
      const names = (arc.labels ?? []).map((l) => l.name);
      if (names.length === 0) add(arc.name, null);
      else for (const name of names) add(arc.name, name);
    }
  }
  return lanes;
}

// Which document a kit annotates. The kit's own source_uid when it has one,
// otherwise whatever its anchors say — a kit that was never given a source_uid
// still has the docid written on every time it recorded.
export function document_key(block) {
  if (block.docid) return block.docid;
  const named = (block.nodes ?? []).find((n) => n.docid);
  return named ? named.docid : NO_DOCID;
}

export const NO_DOCID = "(no docid)";

// Kits grouped by the document they annotate, so several passes over one
// recording are drawn on one set of lanes instead of one set each — a task
// annotated twice over was otherwise the same document twice down the page,
// with a screenful of nothing between the two.
//
// The merge is a drawing, not a graph. Each kit keeps its own tree, its own
// iids and its own anchors: two kits meeting at the same time do NOT share an
// anchor, and the structure panel stays inside the kit it opened. That's why
// spans carry kit_id from here on, and why a span's identity is the pair.
export function group_by_document(blocks) {
  const documents = [];
  const by_key = new Map();

  for (const block of blocks) {
    const docid = document_key(block);
    let doc = by_key.get(docid);
    if (!doc) {
      doc = { docid, kits: [], arcs: [], nodes: [] };
      by_key.set(docid, doc);
      documents.push(doc);
    }
    doc.kits.push(block);
    doc.arcs.push(...block.arcs);
    doc.nodes.push(...block.nodes);
  }
  return documents;
}

// A kit's rows, joined: every span with its anchors' times filled in and its
// labels attached. `beg` and `end` already come resolved from GraphArc#to_row,
// but an arc whose anchor was deleted out from under it has neither, and one
// of those should be visible as a broken span rather than silently absent.
export function resolve_block(block) {
  const anchors = (block.nodes ?? []).map(
    (n) => ({ ...n, kit_id: block.kit_id, time: to_number(n.time) })
  );
  const time_of = new Map(anchors.map((n) => [n.iid, n.time]));

  const labels_by_arc = new Map();
  for (const label of block.labels ?? []) {
    if (!labels_by_arc.has(label.arc_iid)) labels_by_arc.set(label.arc_iid, []);
    labels_by_arc.get(label.arc_iid).push(label);
  }

  const arcs = (block.arcs ?? []).map((arc) => {
    const labels = labels_by_arc.get(arc.iid) ?? [];
    // Stamped here so a span merged into a document still names its kit — its
    // iid alone doesn't, being unique only within the tree.
    const beg = pick_time(arc.beg, time_of.get(arc.beg_iid));
    const end = pick_time(arc.end, time_of.get(arc.end_iid));
    return {
      ...arc,
      kit_id: block.kit_id,
      beg,
      end,
      labels,
      // Keyed access for the lane that wants one particular label.
      label_values: Object.fromEntries(labels.map((l) => [l.name, l.value])),
      // A span missing an anchor can't be placed. It's still a row, and the
      // inspector still has something to say about it.
      dangling: beg === null || end === null
    };
  });

  return { ...block, nodes: anchors, arcs, time_of };
}

// The whole task's time span, across every kit. Kits are separate recordings
// that each start near zero, so drawing them on one scale is what makes their
// lengths comparable at a glance.
export function extent(blocks) {
  let beg = null;
  let end = null;
  for (const block of blocks) {
    for (const node of block.nodes ?? []) {
      const t = to_number(node.time);
      if (t === null) continue;
      if (beg === null || t < beg) beg = t;
      if (end === null || t > end) end = t;
    }
  }
  if (beg === null) return { beg: 0, end: 1 };
  if (end - beg < 1e-6) return { beg, end: beg + 1 }; // a single anchor still needs a width
  return { beg, end };
}

// The spans of one lane, in one kit: those whose arc name matches and which
// carry the label this lane is for, packed into rows.
//
// Packed over the whole recording rather than over the window in view, so the
// rows don't reshuffle as you pan across a lane and a span doesn't jump to a
// different height when the one it overlapped scrolls off the left edge.
export function lane_spans(block, lane) {
  const spans = block.arcs.filter(
    (arc) =>
      arc.name === lane.arc_name &&
      !arc.dangling &&
      (lane.label_name === null || Object.hasOwn(arc.label_values, lane.label_name))
  );
  return pack(spans);
}

// Which of those spans touch the window. Culling here rather than in the
// markup is what keeps a large task drawable: zoomed in on ten seconds of one
// kit, the SVG holds the spans of those ten seconds and not the eighty
// thousand behind them.
export function in_view(spans, view) {
  return spans.filter((s) => s.end >= view.beg && s.beg <= view.end);
}

// Greedy interval packing: first row whose last span has already ended.
// Segments in a lane don't normally overlap, but comments do, and a lane that
// silently drew one span on top of another would be lying about the data.
export function pack(spans) {
  const rows = []; // row index → end time of the last span placed on it
  return spans
    .slice()
    // Ties broken by kit then iid: a document holding two kits has two spans
    // that can both be iid 14, and the order has to be settled all the same.
    .sort((a, b) => a.beg - b.beg || (a.kit_id ?? 0) - (b.kit_id ?? 0) || a.iid - b.iid)
    .map((span) => {
      let row = rows.findIndex((last) => last <= span.beg);
      if (row === -1) row = rows.push(span.end) - 1;
      else rows[row] = span.end;
      return { ...span, row };
    });
}

// How many rows deep a packed lane goes. A lane with nothing in it still
// occupies one, so its name has somewhere to sit.
export function lane_depth(spans) {
  return spans.reduce((deepest, s) => Math.max(deepest, s.row + 1), 1);
}

// Zoom keeping the time under the pointer where it is. `factor` above 1 zooms
// in. Clamped to the task's extent so you can't lose the drawing off-screen,
// and to a floor of a millisecond so it stops somewhere.
export function zoom_at(view, factor, at, limit) {
  const width = (view.end - view.beg) / factor;
  const full = limit.end - limit.beg;
  const clamped = Math.min(Math.max(width, 0.001), full);
  const fraction = view.end > view.beg ? (at - view.beg) / (view.end - view.beg) : 0.5;
  return clamp_view({ beg: at - fraction * clamped, end: at + (1 - fraction) * clamped }, limit);
}

export function pan_by(view, seconds, limit) {
  return clamp_view({ beg: view.beg + seconds, end: view.end + seconds }, limit);
}

// Slide a window back inside the extent without changing its width — panning
// off the end parks you at the end rather than scrolling into nothing.
export function clamp_view(view, limit) {
  const width = view.end - view.beg;
  if (width >= limit.end - limit.beg) return { beg: limit.beg, end: limit.end };
  if (view.beg < limit.beg) return { beg: limit.beg, end: limit.beg + width };
  if (view.end > limit.end) return { beg: limit.end - width, end: limit.end };
  return view;
}

// What the inspector draws: the selected span, the anchors at each end, and
// every other span of this kit that shares one of those anchors. Anchor
// sharing is the structural fact a lane view can't show — two spans meeting at
// one anchor and two spans merely abutting at equal times look identical on a
// timeline and are not the same graph.
export function neighbourhood(block, arc) {
  const ends = new Set([arc.beg_iid, arc.end_iid]);
  const anchors = (block.nodes ?? []).filter((n) => ends.has(n.iid));
  const neighbours = (block.arcs ?? []).filter(
    (a) => a.iid !== arc.iid && (ends.has(a.beg_iid) || ends.has(a.end_iid))
  );
  return { arc, anchors, neighbours };
}

// Ticks at a round interval — 1, 2, 5, 10, 20, 50… seconds — chosen so the
// window holds roughly `target` of them however far it's zoomed.
export function ticks(view, target = 10) {
  const rough = (view.end - view.beg) / Math.max(target, 1);
  if (!(rough > 0)) return [];
  const magnitude = Math.pow(10, Math.floor(Math.log10(rough)));
  const step = [1, 2, 5, 10].map((m) => m * magnitude).find((s) => s >= rough) ?? magnitude * 10;
  // Counted off the step rather than accumulated, and snapped to the step's own
  // precision — 28 × 0.05 is 1.4000000000000001 in binary floating point, and a
  // ruler is the wrong place to find that out.
  const decimals = Math.max(0, -Math.floor(Math.log10(step)) + 1);
  const out = [];
  for (let k = Math.ceil(view.beg / step); k * step <= view.end; k++) {
    out.push(Number((k * step).toFixed(decimals)));
  }
  return out;
}

// mm:ss.mmm when there are minutes to speak of, seconds otherwise.
export function format_time(t) {
  if (t === null || t === undefined || Number.isNaN(t)) return "";
  const sign = t < 0 ? "-" : "";
  const abs = Math.abs(t);
  if (abs < 60) return `${sign}${abs.toFixed(3).replace(/0+$/, "").replace(/\.$/, "")}s`;
  const minutes = Math.floor(abs / 60);
  const seconds = abs - minutes * 60;
  return `${sign}${minutes}:${seconds.toFixed(3).padStart(6, "0")}`;
}

function to_number(v) {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isNaN(n) ? null : n;
}

// The arc row's own copy of the time, falling back to the anchor it names.
// They agree when the snapshot is sound; when they don't, the anchor is the
// identity and the copy is the convenience, so the anchor wins.
function pick_time(copy, from_anchor) {
  const anchor = to_number(from_anchor);
  return anchor !== null ? anchor : to_number(copy);
}

// ── the two bars ───────────────────────────────────────────────────────────
// Moving the window and setting how wide it is, as things you drag rather than
// as something the mouse wheel does behind your back. The wheel is left to the
// browser now, so it scrolls the list of kits and nothing else.

// A scrollbar thumb's size says how much of the task you are looking at, which
// is the half of "where am I" a slider can't tell you. Below a few dozen pixels
// it stops being draggable, though, so it has a floor — and once it has one it
// no longer covers the fraction it represents, so the travel has to shrink to
// match or the far end of the task becomes unreachable.
export const MIN_THUMB = 24;

export function thumb_geometry(view, limit, track, min_thumb = MIN_THUMB) {
  const total = limit.end - limit.beg;
  if (!(total > 0) || !(track > 0)) return { left: 0, width: track, travel: 0, movable: false };

  const window_width = Math.min(view.end - view.beg, total);
  const width = Math.min(track, Math.max(min_thumb, (track * window_width) / total));
  const travel = track - width;
  const span = total - window_width; // how much of the task is off-screen
  const fraction = span > 1e-9 ? (view.beg - limit.beg) / span : 0;

  return {
    width,
    travel,
    left: travel * Math.min(Math.max(fraction, 0), 1),
    movable: travel > 0 && span > 1e-9
  };
}

// Where the window lands when the thumb is dragged to `left`.
export function view_from_thumb(left, view, limit, track, min_thumb = MIN_THUMB) {
  const total = limit.end - limit.beg;
  const window_width = Math.min(view.end - view.beg, total);
  const { travel } = thumb_geometry(view, limit, track, min_thumb);
  const span = total - window_width;

  if (travel <= 0 || span <= 1e-9) return { beg: limit.beg, end: limit.beg + window_width };

  const fraction = Math.min(Math.max(left / travel, 0), 1);
  const beg = limit.beg + fraction * span;
  return { beg, end: beg + window_width };
}

// The narrowest the zoom bar will go. The buttons still go further; this is the
// end of the bar's own travel, picked so the useful range isn't all crammed
// into its last millimetre.
export const MIN_WINDOW = 0.1;

// 0 is the whole task, 1 is as far in as the bar goes. Logarithmic, because a
// linear one spends almost all its length between "everything" and "most of
// everything" and then crosses four orders of magnitude in the last few pixels.
export function zoom_slider_value(view, limit, min_window = MIN_WINDOW) {
  const total = limit.end - limit.beg;
  const floor = Math.min(min_window, total);
  if (!(total > floor)) return 0;

  const window_width = Math.min(Math.max(view.end - view.beg, floor), total);
  const at = Math.log(window_width / total) / Math.log(floor / total);
  // Showing the whole task makes that Math.log(1) over a negative, which is -0.
  // It behaves like 0 in every sum here, but it is not 0 to anything comparing
  // the two, so it doesn't leave this function.
  return at === 0 ? 0 : at;
}

// And back: the window that slider position asks for, held on its own centre so
// zooming doesn't also walk sideways.
export function view_from_zoom_slider(value, view, limit, min_window = MIN_WINDOW) {
  const total = limit.end - limit.beg;
  const floor = Math.min(min_window, total);
  if (!(total > floor)) return { beg: limit.beg, end: limit.end };

  const at = Math.min(Math.max(value, 0), 1);
  const window_width = total * Math.pow(floor / total, at);
  const centre = (view.beg + view.end) / 2;
  return clamp_view({ beg: centre - window_width / 2, end: centre + window_width / 2 }, limit);
}

// ── naming a document ──────────────────────────────────────────────────────

// What to call a document on screen. A docid is routinely a URL or an S3 key,
// and the part that tells two of them apart is almost always at the end:
// "s3://my-bucket/recordings/0703D8C6…_passage_reading.wav" reads as that last
// segment and nothing else. The full value is still worth having, so callers
// keep it as a tooltip.
//
// Given the whole set at once, because a basename on its own isn't always
// enough: a/take1.wav and b/take1.wav would be two rows with one name and no
// way to pick between them. Anything that collides takes another segment from
// its path, and again, until the names are distinct or the path runs out.
export function document_labels(docids) {
  const parts = new Map(docids.map((d) => [ d, path_segments(d) ]));
  const depth = new Map(docids.map((d) => [ d, 1 ]));
  const label_of = (d) => parts.get(d).slice(-depth.get(d)).join("/") || d;

  for (;;) {
    const sharing = new Map();
    for (const docid of docids) {
      const label = label_of(docid);
      if (!sharing.has(label)) sharing.set(label, []);
      sharing.get(label).push(docid);
    }

    let grew = false;
    for (const group of sharing.values()) {
      if (group.length < 2) continue;
      for (const docid of group) {
        // Nothing left to add means two docids really do end the same way;
        // they keep the name they have rather than looping for ever.
        if (depth.get(docid) >= parts.get(docid).length) continue;
        depth.set(docid, depth.get(docid) + 1);
        grew = true;
      }
    }
    if (!grew) return new Map(docids.map((d) => [ d, label_of(d) ]));
  }
}

// A query string on a signed URL is noise, and the scheme and host are the
// parts every docid in a task has in common.
function path_segments(docid) {
  const clean = String(docid ?? "").split(/[?#]/)[0];
  const segments = clean.split("/").filter((s) => s.length > 0);
  return segments.length ? segments : [ clean ];
}
