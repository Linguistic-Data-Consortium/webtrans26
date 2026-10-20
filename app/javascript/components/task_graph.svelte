<script>
    // The task's annotation graph, drawn.
    //
    // Mounted by app/views/tasks/graph.html.haml at
    // /projects/:project_id/tasks/:id/graph. It asks the same URL for JSON,
    // which snapshots every kit in the task into graph_nodes / graph_arcs /
    // graph_labels and hands the rows back; everything below is a drawing of
    // those rows and nothing else.
    //
    // Two views of the same data, because they answer different questions.
    // The lanes say what the task looks like — time across, one row per kind of
    // thing annotated, spans as rects. The inspector says what one span
    // actually *is*: the anchors at its ends, its arc node, its labels, and the
    // other spans hanging off the same anchors. A timeline can't show anchor
    // sharing — two spans meeting at one anchor and two spans merely abutting
    // at equal times draw identically and are different graphs — so the
    // structure gets its own picture rather than a caption.
    //
    // Zoom is a computed x scale, not an SVG viewBox. A viewBox would be less
    // code and would scale the text with it, which is the wrong way round:
    // zooming in should reveal more words, not enlarge the few already there.
    // The scale also lets spans outside the window be dropped before they reach
    // the markup, which is what keeps a long task responsive.
    //
    // Nothing here knows the annotation vocabulary. Lanes come out of the data's
    // own `name` columns, so a group the client invents gets a lane, a colour
    // and a checkbox the first time one is annotated.

    import { SvelteSet } from 'svelte/reactivity';
    import { getp } from '../lib/ldcjs/getp';
    import {
        lanes_for, resolve_block, extent, lane_spans, lane_depth, in_view,
        zoom_at, pan_by, clamp_view, neighbourhood, ticks, format_time,
        group_by_document, document_key,
        thumb_geometry, view_from_thumb, zoom_slider_value, view_from_zoom_slider,
        document_labels
    } from './task_graph_layout';

    let { task_id, project_id, task_name = '', project_name = '' } = $props();

    const url = `/projects/${project_id}/tasks/${task_id}/graph.json`;

    let payload   = $state(null);
    let loading   = $state(true);
    // Which kind of load is in flight. An ordinary one replays only the kits
    // that have been annotated since their rows were written, which is usually
    // none of them — saying "snapshotting every kit" while that goes on claims
    // work that mostly isn't happening. Re-snapshot really does do all of them.
    let rebuilding = $state(false);
    let error     = $state(null);
    let elapsed   = $state(0);

    // Which lanes are drawn, by lane key. A lane absent from the map is shown,
    // so a newly invented group appears without anyone opting in.
    let hidden    = $state({});
    let collapsed = $state({});    // docid → the document is rolled up
    // Docids drawn, and nothing more: unticked is unticked, and all of them
    // unticked is a blank drawing. Set to the first document when the payload
    // arrives.
    let picked    = $state(new SvelteSet());
    let selected  = $state(null);  // { kit_id, iid } — what the inspector holds
    // The structure pane is shut to begin with: it is a third of the window, and
    // the drawing is the thing people came for. Clicking a span opens it, which
    // is exactly when it has something to say.
    let pane_open = $state(false);
    let filter    = $state('');   // narrows the document picker's list
    let picking   = $state(false); // the picker panel is open

    let view      = $state({ beg: 0, end: 1 });
    let width     = $state(1000);  // the drawing area, in px, measured from the DOM

    const GUTTER  = 190;           // room for the lane names down the left
    const LANE_H  = 22;            // one packed row of spans
    const RULER_H = 28;
    const HEAD_H  = 30;            // a kit's header strip

    // How wide the window is when the page opens. A whole task at once is a
    // shape, not a transcript — at that scale a segment is a few pixels and
    // none of the text fits. Ten seconds is close enough in to read words on
    // the first paint; Fit is one button away for the overview. A recording
    // shorter than this simply shows all of itself.
    const INITIAL_SECONDS = 10;

    // Rows → drawable, once per payload rather than once per repaint.
    //
    // Kits are resolved individually — the structure panel needs each one's own
    // graph, because iids and anchors belong to a tree — and then grouped by
    // the document they annotate. A recording annotated twice over is drawn
    // once, on one set of lanes, rather than twice down the page with a
    // screenful of nothing between the passes.
    const blocks    = $derived((payload?.kits ?? []).map(resolve_block));
    const documents = $derived(group_by_document(blocks));
    const lanes     = $derived(lanes_for(documents));
    const limit     = $derived(extent(blocks));

    // Which documents are drawn. Empty means all of them, so a fresh page shows
    // the task rather than nothing, and a docid the task gains later is in
    // without anyone opting it in.
    const chosen_docs = $derived(documents.filter((d) => picked.has(d.docid)));
    // The picker's own list, narrowed by what's typed into it.
    const listed_docs = $derived(
        filter.trim() === ''
            ? documents
            : documents.filter((d) => d.docid.toLowerCase().includes(filter.trim().toLowerCase()))
    );
    const shown_lanes = $derived(lanes.filter((l) => !hidden[l.key]));

    // What each document is called on screen: the end of its docid, which is
    // the part that tells two of them apart. Worked out over the whole set, so
    // two recordings whose paths end the same way still get distinct names.
    // The full docid stays as the tooltip wherever a name is shown.
    const doc_names = $derived(document_labels(documents.map((d) => d.docid)));
    const doc_name = (docid) => doc_names.get(docid) ?? docid;

    // Spans carry kit_id and nothing else about their kit — one lookup here
    // beats a copy of the same two strings on every row.
    const kit_of = $derived(new Map(blocks.map((b) => [ b.kit_id, b ])));

    // Spans are packed here, once, over the whole recording — so lane heights
    // are fixed and panning doesn't make rows reshuffle underneath you.
    const laid_out = $derived(chosen_docs.map((doc) => {
        const is_collapsed = !!collapsed[doc.docid];
        const rows = is_collapsed ? [] : shown_lanes.map((lane) => {
            const spans = lane_spans(doc, lane);
            return { lane, spans, depth: lane_depth(spans) };
        });
        const height = rows.reduce((h, r) => h + r.depth * LANE_H, 0) + (is_collapsed ? 0 : 10);
        return { doc, rows, height, collapsed: is_collapsed };
    }));

    // Where each document's header sits, accumulated once instead of re-summed
    // inside the markup.
    const placed = $derived.by(() => {
        let y = 0; // the ruler is a separate svg above the scroller now
        return laid_out.map((b) => {
            const top = y;
            y += HEAD_H + b.height;
            return { ...b, top };
        });
    });
    const svg_height = $derived(
        laid_out.reduce((h, b) => h + HEAD_H + b.height, 0)
    );

    const totals = $derived(blocks.reduce(
        (t, b) => ({
            anchors: t.anchors + b.nodes.length,
            spans: t.spans + b.arcs.length,
            labels: t.labels + b.labels.length,
            dangling: t.dangling + b.arcs.filter((a) => a.dangling).length
        }),
        { anchors: 0, spans: 0, labels: 0, dangling: 0 }
    ));

    const inspecting = $derived.by(() => {
        if (!selected) return null;
        const block = blocks.find((b) => b.kit_id === selected.kit_id);
        const arc = block?.arcs.find((a) => a.iid === selected.iid);
        return arc ? { block, ...neighbourhood(block, arc) } : null;
    });

    const plot_width = $derived(Math.max(width - GUTTER, 80));
    // Roughly how wide an 11px character is. Enough to decide whether a label
    // fits where it is going; measuring for real means getComputedTextLength
    // per span, on every repaint, for spans that are mostly off-screen.
    const CHAR_W = 5.6;
    // How many of them fit beside the document's name. Naming kits by id *and*
    // uid makes that line long enough to run off the edge, and a line cut with
    // an ellipsis reads better than one that simply stops — the whole of it is
    // in the tooltip either way.
    const summary_room = $derived(Math.max(Math.floor(plot_width / CHAR_W), 20));
    const x = $derived((t) => GUTTER + ((t - view.beg) / (view.end - view.beg)) * plot_width);
    const zoomed = $derived((limit.end - limit.beg) / (view.end - view.beg));

    // A plain load reuses the rows of any kit nobody has annotated since they
    // were written; Re-snapshot replays every kit whatever their state.
    async function load(rebuild = false) {
        loading = true;
        rebuilding = rebuild;
        error = null;
        const began = performance.now();
        try {
            const body = await getp(rebuild ? `${url}?rebuild=1` : url);
            if (body && body.error) { error = body.error; return; }

            const resolved = (body.kits ?? []).map(resolve_block);

            // One document to begin with, not all of them. A task is routinely
            // dozens of recordings, and opening on the lot is a wall of lanes
            // with no way to tell at a glance which rows belong together — the
            // picker is right there, and this way it starts from something
            // readable. The time axis still spans the whole task, so switching
            // documents doesn't move the ruler under you.
            const first = group_by_document(resolved)[0];
            picked = new SvelteSet(first ? [ first.docid ] : []);

            const span = extent(resolved);
            view = clamp_view({ beg: span.beg, end: span.beg + INITIAL_SECONDS }, span);

            // Last, and deliberately: `payload` is what the drawing reads, and
            // an empty selection means every document. Setting it before the
            // selection is decided leaves a state — however briefly — that says
            // draw all of them. Svelte batches these, so nothing renders in
            // between today; this doesn't depend on that staying true.
            payload = body;
            elapsed = Math.round(performance.now() - began);
        } catch (e) {
            error = String(e && e.message ? e.message : e);
        } finally {
            loading = false;
        }
    }

    // ── the position bar and the zoom bar ──────────────────────────────
    // The window is moved and sized by dragging these, not by the wheel. The
    // wheel used to pan and zoom, so the drawing moved under the pointer when
    // you were only trying to get down the page, and nothing on screen said how
    // much of the task you were looking at. The wheel now belongs to the
    // browser and scrolls the list of kits, which is all it ever should have.
    let position_track = $state(0);   // the bars' own widths, measured
    let zoom_track     = $state(0);
    let drag           = $state(null);

    const ZOOM_THUMB  = 18;
    const zoom_travel = $derived(Math.max(zoom_track - ZOOM_THUMB, 0));
    const thumb       = $derived(thumb_geometry(view, limit, position_track));
    const zoom_value  = $derived(zoom_slider_value(view, limit));
    const zoom_left   = $derived(zoom_travel * zoom_value);

    // One drag for both bars. The pointer is captured so it keeps being
    // followed once it leaves the few pixels the thumb occupies — without that,
    // a quick drag loses the thumb as soon as it outruns it.
    function thumb_down(kind, from) {
        return (event) => {
            event.preventDefault();
            event.currentTarget.setPointerCapture(event.pointerId);
            drag = { kind, at: event.clientX, from };
        };
    }
    function thumb_move(event) {
        if (!drag) return;
        const to = drag.from + (event.clientX - drag.at);
        if (drag.kind === 'position') view = view_from_thumb(to, view, limit, position_track);
        else view = view_from_zoom_slider(zoom_travel > 0 ? to / zoom_travel : 0, view, limit);
    }
    function thumb_up(event) {
        if (!drag) return;
        event.currentTarget.releasePointerCapture?.(event.pointerId);
        drag = null;
    }

    // Clicking the track beside the thumb pages, the way a scrollbar does; on
    // the zoom bar there is nothing to page through, so it goes where clicked.
    function position_track_down(event) {
        if (drag) return;
        const box = event.currentTarget.getBoundingClientRect();
        pan(event.clientX - box.left > thumb.left + thumb.width / 2 ? PAGE : -PAGE);
    }
    function zoom_track_down(event) {
        if (drag) return;
        const box = event.currentTarget.getBoundingClientRect();
        view = view_from_zoom_slider(
            zoom_travel > 0 ? (event.clientX - box.left - ZOOM_THUMB / 2) / zoom_travel : 0,
            view, limit
        );
    }

    // Both bars take focus and answer the arrow keys: a control reachable only
    // by mouse is half a control, and these two are now the whole of how the
    // window is moved by pointer.
    function bar_key(kind) {
        return (event) => {
            if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
            event.preventDefault();
            const way = event.key === 'ArrowRight' ? 1 : -1;
            if (kind === 'position') pan(way * 0.1);
            else view = view_from_zoom_slider(zoom_value + way * 0.05, view, limit);
        };
    }

    // Panning is buttons, not a drag. On a timeline this dense a drag is an
    // awkward gesture — it fights the click that selects a span, and there is
    // nowhere to grab that isn't already something — so the window is moved by
    // controls that say what they do.
    const PAGE = 0.8; // one press moves most of a window, keeping some overlap

    function pan(fraction) {
        view = pan_by(view, (view.end - view.beg) * fraction, limit);
    }
    function to_start() {
        const width_now = view.end - view.beg;
        view = clamp_view({ beg: limit.beg, end: limit.beg + width_now }, limit);
    }
    function to_end() {
        const width_now = view.end - view.beg;
        view = clamp_view({ beg: limit.end - width_now, end: limit.end }, limit);
    }

    // Whether there is anything left that way — the controls go flat rather
    // than staying lit and doing nothing.
    const at_start = $derived(view.beg <= limit.beg + 1e-9);
    const at_end   = $derived(view.end >= limit.end - 1e-9);

    function zoom(factor) {
        view = zoom_at(view, factor, (view.beg + view.end) / 2, limit);
    }
    function fit() { view = { ...limit }; }

    function toggle(docid) {
        collapsed = { ...collapsed, [docid]: !collapsed[docid] };
    }

    // Choosing documents. An empty set means every one, so "all" is the state
    // the page starts in rather than a set that has to be kept up to date;
    // clearing the last tick returns to it instead of drawing nothing.
    // The set is literally what's drawn — no spare meaning for the empty one.
    // It used to stand for "all of them", which made unticking the last box
    // tick every other box instead, and left no way to ask for nothing.
    function toggle_doc(docid) {
        const next = new SvelteSet(picked);
        if (next.has(docid)) next.delete(docid); else next.add(docid);
        picked = next;
    }
    const all_docs  = () => (picked = new SvelteSet(documents.map((d) => d.docid)));
    const none_docs = () => (picked = new SvelteSet());
    const only_docs = (docs) => (picked = new SvelteSet(docs.map((d) => d.docid)));
    const doc_shown = (docid) => picked.has(docid);

    // What a document's header says about the kits under it. One kit names
    // itself; several say how many and who, since that is the question a
    // doubly-annotated recording raises.
    function doc_summary(doc) {
        const users = [ ...new Set(doc.kits.map((k) => k.user).filter(Boolean)) ];
        const kits = doc.kits.length === 1
            ? `kit ${kit_label(doc.kits[0])}`
            : `${doc.kits.length} kits (${doc.kits.map(kit_label).join(', ')})`;
        const anchors = doc.nodes.length;
        const spans = doc.arcs.length;
        return `${kits} · ${users.join(', ') || 'unassigned'} · ${anchors} anchors, ${spans} spans`;
    }

    // The plot takes focus, so the whole drawing is reachable without a mouse:
    // arrows pan by a tenth of the window, +/− zoom, Home fits.
    function key(event) {
        const step = (view.end - view.beg) / 10;
        const moves = {
            ArrowLeft:  () => (view = pan_by(view, -step, limit)),
            ArrowRight: () => (view = pan_by(view, step, limit)),
            '+':        () => zoom(1.6),
            '=':        () => zoom(1.6),
            '-':        () => zoom(1 / 1.6),
            Home:       fit
        };
        const move_it = moves[event.key];
        if (move_it) { event.preventDefault(); move_it(); }
    }

    // Zoom to one span, with a tenth of its length either side so its edges
    // aren't flush against the frame.
    function focus(arc) {
        const pad = Math.max((arc.end - arc.beg) * 0.1, 0.05);
        view = clamp_view({ beg: arc.beg - pad, end: arc.end + pad }, limit);
    }

    function measure(node) {
        const observer = new ResizeObserver(() => { width = node.clientWidth; });
        observer.observe(node);
        width = node.clientWidth;
        return { destroy: () => observer.disconnect() };
    }

    function lane_text(arc, lane) {
        if (lane.label_name === null) return arc.name;
        const v = arc.label_values[lane.label_name];
        return v === null || v === undefined ? '' : String(v);
    }

    // A kit is named by both of its identities: the integer the database and
    // the tasks pages use, and the hex uid the tool and the URLs use. Either
    // alone sends you looking the other up.
    const kit_label = (kit) => `${kit.kit_id}/${kit.uid ?? '—'}`;

    const lane_title = (lane) =>
        `${lane.arc_name.replace(/ListItem$/, '')}${lane.label_name ? ` · ${lane.label_name}` : ''}`;

    // A lane's colour comes from its arc name, so a kind of annotation looks the
    // same in every kit and in the inspector. Not from a table — the names
    // aren't known here, which is the point — but by position in the arc names
    // this task actually holds, stepped round the wheel by the golden angle so
    // any number of them stay far apart. Hashing the name was the first go and
    // it put segments and sections on nearly the same green.
    const arc_names = $derived([ ...new Set(lanes.map((l) => l.arc_name)) ]);
    function hue(name) {
        const i = arc_names.indexOf(name);
        return (210 + (i < 0 ? 0 : i) * 137.5) % 360; // start on blue, not red
    }
    const fill = (name) => `hsl(${hue(name)} 70% 88%)`;
    const edge = (name) => `hsl(${hue(name)} 55% 45%)`;

    // The header sits in the gutter beside the kit's details, and a uid can be
    // longer than the room there — so it's cut here rather than left to run
    // over the text next to it.
    const short = (s, n) => {
        const t = String(s ?? '');
        return t.length > n ? `${t.slice(0, n - 1)}…` : t;
    };

    const btn = 'px-2 py-1 text-sm border border-gray-400 rounded bg-white hover:bg-gray-100 disabled:opacity-50';

    load();
</script>

<div class="py-4">
    <div class="flex items-baseline justify-between flex-wrap gap-2 mb-3">
        <div>
            <h1 class="text-xl font-semibold">{task_name} — annotation graph</h1>
            <div class="text-sm text-gray-600">
                {project_name}
                {#if payload}
                    · {payload.kits.length} of {payload.kit_count} kits over
                    {documents.length} {documents.length === 1 ? 'document' : 'documents'}
                    · {totals.anchors} anchors, {totals.spans} spans, {totals.labels} labels
                    · {payload.reused === payload.kits.length && payload.kits.length > 0
                        ? 'already up to date'
                        : payload.reused > 0
                            ? `${payload.kits.length - payload.reused} re-snapshotted, ${payload.reused} already current`
                            : 'snapshotted'} in {elapsed}ms
                {/if}
            </div>
        </div>
        <div class="flex gap-2 items-center">
            <button class={btn} onclick={() => (pane_open = !pane_open)} aria-expanded={pane_open}
                    title="The anchors, arc node and labels of the span you click">
                Structure
            </button>
            <button class={btn} onclick={() => (picking = !picking)} aria-expanded={picking}>
                Documents ({picked.size}/{documents.length})
            </button>
            <button class={btn} onclick={() => load(true)} disabled={loading}
                    title="Replay every kit, even the ones nothing has changed in">
                Re-snapshot
            </button>
        </div>
    </div>

    <!-- Which recordings to draw. A task can hold more documents than fit on a
         screen, so the list has its own search and lives behind a button rather
         than sitting open above the plot. -->
    {#if picking}
        <div class="mb-3 border border-gray-300 rounded p-3">
            <div class="flex gap-2 items-center mb-2">
                <input class="border border-gray-400 rounded px-2 py-1 text-sm flex-1"
                       placeholder="search documents" bind:value={filter} />
                <button class={btn} onclick={all_docs}>All</button>
                <button class={btn} onclick={none_docs} disabled={picked.size === 0}>None</button>
                <button class={btn} onclick={() => only_docs(listed_docs)}
                        disabled={listed_docs.length === 0}>Only these</button>
                <button class={btn} onclick={() => (picking = false)}>Done</button>
            </div>
            <div class="max-h-56 overflow-y-auto grid grid-cols-2 md:grid-cols-3 gap-x-4 gap-y-1">
                {#each listed_docs as doc (doc.docid)}
                    <label class="flex items-center gap-2 cursor-pointer text-sm truncate"
                           title={doc.docid}>
                        <input type="checkbox" checked={doc_shown(doc.docid)}
                               onchange={() => toggle_doc(doc.docid)} />
                        <span class="truncate">{doc_name(doc.docid)}</span>
                        {#if doc.kits.length > 1}
                            <span class="text-xs text-gray-500 shrink-0">×{doc.kits.length}</span>
                        {/if}
                    </label>
                {:else}
                    <div class="text-sm text-gray-600">No document matches that.</div>
                {/each}
            </div>
        </div>
    {/if}

    {#if payload && (payload.truncated > 0 || payload.unopened > 0)}
        <div class="mb-3 text-sm border border-amber-400 bg-amber-50 rounded p-2">
            {#if payload.truncated > 0}
                Only the first {payload.kits.length + payload.unopened} kits of this task were
                snapshotted; {payload.truncated} more were not drawn. A snapshot replays every
                annotation of every kit, so the page bounds it rather than risk the request.
                <a class="underline" href="/projects/{project_id}/tasks/{task_id}/graph?limit=0">Draw
                the whole task anyway</a> — it will be slow.
            {/if}
            {#if payload.unopened > 0}
                {payload.unopened}
                {payload.unopened === 1 ? 'kit has' : 'kits have'} never been opened, so
                {payload.unopened === 1 ? 'it has' : 'they have'} no annotations to draw.
            {/if}
        </div>
    {/if}

    {#if totals.dangling > 0}
        <div class="mb-3 text-sm border border-red-400 bg-red-50 rounded p-2">
            {totals.dangling} {totals.dangling === 1 ? 'span names an anchor' : 'spans name anchors'}
            that {totals.dangling === 1 ? 'is' : 'are'} not in the graph, so
            {totals.dangling === 1 ? 'it has' : 'they have'} no place on the timeline and
            {totals.dangling === 1 ? "isn't" : "aren't"} drawn. Listed under the plot.
        </div>
    {/if}

    {#if loading}
        <div class="text-gray-600">
            {rebuilding
                ? "Re-snapshotting every kit in this task…"
                : "Reading this task's annotation graph…"}
        </div>
    {:else if error}
        <div class="text-red-600">{error}</div>
    {:else if blocks.length === 0}
        <div class="text-gray-600">
            No kit in this task has been annotated yet — no anchors, no spans.
        </div>
    {:else}
        <div class="flex gap-4 items-start">
            <div class="flex-1 min-w-0">
                <!-- Zoom, and one checkbox per lane. The lane list is whatever
                     the data holds, so an invented group turns up on its own. -->
                <div class="flex flex-wrap gap-x-4 gap-y-2 items-center mb-2 text-sm">
                    <div class="flex gap-1">
                        <button class={btn} onclick={to_start} disabled={at_start}
                                title="To the start">⇤</button>
                        <button class={btn} onclick={() => pan(-PAGE)} disabled={at_start}
                                title="Back">←</button>
                        <button class={btn} onclick={() => zoom(1 / 1.6)}
                                title="Zoom out">−</button>
                        <button class={btn} onclick={fit} title="The whole task">Fit</button>
                        <button class={btn} onclick={() => zoom(1.6)}
                                title="Zoom in">+</button>
                        <button class={btn} onclick={() => pan(PAGE)} disabled={at_end}
                                title="Forward">→</button>
                        <button class={btn} onclick={to_end} disabled={at_end}
                                title="To the end">⇥</button>
                    </div>
                    <!-- The zoom bar. A fixed thumb, because there is no
                         "how much of it am I seeing" to show here — only a
                         position between the whole task and as far in as it
                         goes, and the scale between those is logarithmic. -->
                    <div class="flex items-center gap-2">
                        <span class="text-gray-500">Zoom</span>
                        <!-- svelte-ignore a11y_no_static_element_interactions -->
                        <div class="relative h-4 w-40 rounded bg-gray-100 border border-gray-300
                                    cursor-pointer select-none"
                             bind:clientWidth={zoom_track}
                             onpointerdown={zoom_track_down}
                             data-testid="zoom-bar">
                            <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
                            <div class="absolute top-0 h-full rounded bg-gray-400 hover:bg-gray-500
                                        focus:outline focus:outline-2 focus:outline-blue-500
                                        {drag?.kind === 'zoom' ? 'bg-gray-600 cursor-grabbing' : 'cursor-grab'}"
                                 style="left:{zoom_left}px;width:{ZOOM_THUMB}px"
                                 role="slider" tabindex="0"
                                 aria-label="Zoom"
                                 aria-valuemin="0" aria-valuemax="100"
                                 aria-valuenow={Math.round(zoom_value * 100)}
                                 aria-valuetext="{zoomed.toFixed(1)} times"
                                 onpointerdown={thumb_down('zoom', zoom_left)}
                                 onpointermove={thumb_move}
                                 onpointerup={thumb_up}
                                 onpointercancel={thumb_up}
                                 onkeydown={bar_key('zoom')}
                                 data-testid="zoom-thumb"></div>
                        </div>
                    </div>
                    <span class="text-gray-600 tabular-nums">
                        {format_time(view.beg)} – {format_time(view.end)} ({zoomed.toFixed(1)}×)
                    </span>
                    <span class="text-gray-500">
                        drag the bars, or use the arrow keys · click a span to inspect it,
                        double-click to zoom to it
                    </span>
                    <div class="flex flex-wrap gap-3 ml-auto">
                        {#each lanes as lane (lane.key)}
                            <label class="flex items-center gap-1 cursor-pointer">
                                <input type="checkbox" checked={!hidden[lane.key]}
                                       onchange={() => (hidden = { ...hidden, [lane.key]: !hidden[lane.key] })} />
                                <span class="inline-block w-3 h-3 rounded-sm border"
                                      style="background:{fill(lane.arc_name)};border-color:{edge(lane.arc_name)}"></span>
                                {lane_title(lane)}
                            </label>
                        {/each}
                    </div>
                </div>

                <div class="border border-gray-300 rounded">
                    {#if chosen_docs.length === 0}
                        <!-- Nothing ticked is a real answer, not an error. Said
                             out loud, because an empty bordered box reads as a
                             page that failed to load. -->
                        <div class="p-4 text-sm text-gray-600">
                            No document is ticked, so there is nothing to draw.
                            Pick one under <span class="font-medium">Documents</span>
                            — or All, for every recording in the task.
                        </div>
                    {:else}
                    <!-- The position bar. Above the ruler and the drawing, not
                         below them: with the kits scrolling under it, a bar at
                         the bottom of the box sits a long way from the times it
                         moves, and off the bottom of the screen on a tall task.
                         Lined up with the drawing rather than the lane names.
                         Its thumb is as wide a share of the track as the window
                         is of the task, so the size of it says how much there is
                         either side. -->
                    <!-- svelte-ignore a11y_no_static_element_interactions -->
                    <div class="border-b border-gray-200 p-1 pl-0" style="padding-left:{GUTTER}px">
                        <div class="relative h-3 rounded bg-gray-100 border border-gray-300
                                    {thumb.movable ? 'cursor-pointer' : ''} select-none"
                             bind:clientWidth={position_track}
                             onpointerdown={position_track_down}
                             data-testid="position-bar">
                            <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
                            <div class="absolute top-0 h-full rounded
                                        focus:outline focus:outline-2 focus:outline-blue-500
                                        {thumb.movable
                                            ? (drag?.kind === 'position'
                                                ? 'bg-gray-600 cursor-grabbing'
                                                : 'bg-gray-400 hover:bg-gray-500 cursor-grab')
                                            : 'bg-gray-300'}"
                                 style="left:{thumb.left}px;width:{thumb.width}px"
                                 role="scrollbar" tabindex="0"
                                 aria-label="Position in the recording"
                                 aria-controls="task-graph-plot"
                                 aria-orientation="horizontal"
                                 aria-valuemin={Math.round(limit.beg)}
                                 aria-valuemax={Math.round(limit.end)}
                                 aria-valuenow={Math.round(view.beg)}
                                 aria-valuetext="{format_time(view.beg)} to {format_time(view.end)}"
                                 onpointerdown={thumb.movable ? thumb_down('position', thumb.left) : null}
                                 onpointermove={thumb_move}
                                 onpointerup={thumb_up}
                                 onpointercancel={thumb_up}
                                 onkeydown={bar_key('position')}
                                 data-testid="position-thumb"></div>
                        </div>
                    </div>
                    <!-- The ruler is its own svg above the scroller, not the top
                         of the drawing: inside it, it scrolled away with the
                         first kit and the times went with it. Same width and
                         same x scale, so the two stay in step. -->
                    <svg class="block" width={width} height={RULER_H}
                         role="presentation" aria-hidden="true">
                        <rect x="0" y="0" width={width} height={RULER_H} fill="#f9fafb" />
                        {#each ticks(view) as t}
                            <line x1={x(t)} y1={RULER_H - 6} x2={x(t)} y2={RULER_H} stroke="#9ca3af" />
                            <text x={x(t)} y={RULER_H - 9} font-size="10" fill="#4b5563"
                                  text-anchor="middle">{format_time(t)}</text>
                        {/each}
                        <line x1="0" y1={RULER_H} x2={width} y2={RULER_H} stroke="#d1d5db" />
                    </svg>

                    <!-- The kits scroll; measured here rather than on the border
                         so the width the drawing uses is the width inside any
                         scrollbar this container grows. -->
                    <div class="overflow-x-hidden overflow-y-auto max-h-[70vh]" use:measure>
                        <!-- role=application because the arrow keys mean pan here,
                             not scroll, and a screen reader should hand them over.
                             Svelte counts <svg> as non-interactive whatever role it
                             is given, so the two warnings that follow from taking
                             focus and handling keys are the ones it can't see past. -->
                        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
                        <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
                        <svg id="task-graph-plot" width={width} height={svg_height}
                             onkeydown={key}
                             role="application" tabindex="0"
                             aria-label="Annotation graph for {task_name}, {format_time(view.beg)} to {format_time(view.end)}"
                             class="block select-none focus:outline focus:outline-2 focus:outline-blue-500">
                        {#each placed as { doc, rows, top, collapsed: is_collapsed } (doc.docid)}
                            <g>
                                <rect x="0" y={top} width={width} height={HEAD_H} fill="#f3f4f6" />
                                <text x="8" y={top + 20} font-size="12" class="cursor-pointer"
                                      role="button" tabindex="0"
                                      aria-expanded={!is_collapsed}
                                      onclick={() => toggle(doc.docid)}
                                      onkeydown={(e) => {
                                          if (e.key === 'Enter' || e.key === ' ') {
                                              e.preventDefault();
                                              toggle(doc.docid);
                                          }
                                      }}>
                                    {is_collapsed ? '▸' : '▾'} {short(doc_name(doc.docid), 20)}
                                    <title>{doc.docid}</title>
                                </text>
                                <text x={GUTTER} y={top + 20} font-size="11" fill="#6b7280">
                                    {short(doc_summary(doc), summary_room)}
                                    <title>{doc_summary(doc)}</title>
                                </text>
                            </g>

                            {#each rows as row, j}
                                {@const lane_top = top + HEAD_H
                                    + rows.slice(0, j).reduce((h, r) => h + r.depth * LANE_H, 0)}
                                <g>
                                    <text x="16" y={lane_top + 14} font-size="11" fill="#374151">
                                        {lane_title(row.lane)}
                                    </text>
                                    <line x1={GUTTER} y1={lane_top + row.depth * LANE_H}
                                          x2={width} y2={lane_top + row.depth * LANE_H} stroke="#f3f4f6" />
                                    <!-- Keyed by kit and iid: a document can hold two
                                         kits, and an iid is unique within a tree only. -->
                                    {#each in_view(row.spans, view) as span (`${span.kit_id}:${span.iid}`)}
                                        <!-- Where the span really is, and the part
                                             of it there is room to draw. The rect is
                                             clamped so it doesn't reach into the lane
                                             names or past the right edge; the label is
                                             placed off the unclamped pair, so it is
                                             fixed to the span and scrolls with it. -->
                                        {@const sx1 = x(span.beg)}
                                        {@const sx2 = x(span.end)}
                                        {@const x1 = Math.max(sx1, GUTTER)}
                                        {@const x2 = Math.min(sx2, width)}
                                        {@const y1 = lane_top + span.row * LANE_H + 2}
                                        {@const chosen = selected
                                            && selected.kit_id === span.kit_id
                                            && selected.iid === span.iid}
                                        {@const clip = `clip-${span.kit_id}-${row.lane.key.replace(/\W/g, '')}-${span.iid}`}
                                        {@const kit = kit_of.get(span.kit_id)}
                                        <!-- Mouse only, deliberately: a lane holds
                                             thousands of these, and a tab stop
                                             apiece would bury every other control
                                             on the page. The plot itself takes
                                             focus and the keys pan and zoom it. -->
                                        <!-- svelte-ignore a11y_click_events_have_key_events -->
                                        <!-- svelte-ignore a11y_no_static_element_interactions -->
                                        <g class="cursor-pointer"
                                           onclick={() => {
                                               selected = { kit_id: span.kit_id, iid: span.iid };
                                               pane_open = true;
                                           }}
                                           ondblclick={() => focus(span)}>
                                            <rect x={x1} y={y1} width={Math.max(x2 - x1, 1)}
                                                  height={LANE_H - 4} rx="2"
                                                  fill={fill(row.lane.arc_name)}
                                                  stroke={chosen ? '#111827' : edge(row.lane.arc_name)}
                                                  stroke-width={chosen ? 2 : 1} />
                                            {#if sx2 - sx1 > 26}
                                                {@const label = lane_text(span, row.lane)}
                                                {@const fits = label.length * CHAR_W <= sx2 - sx1 - 8}
                                                <clipPath id={clip}>
                                                    <rect x={x1 + 3} y={y1}
                                                          width={Math.max(x2 - x1 - 6, 1)} height={LANE_H - 4} />
                                                </clipPath>
                                                <!-- pointer-events:none so the rect
                                                     under it is the only target: a
                                                     long label overhangs the span
                                                     next door and would otherwise
                                                     swallow its clicks. -->
                                                <!-- Centred in the span itself — on the
                                                     times of its endpoints, not on
                                                     whatever part of it happens to be on
                                                     screen. Placing it off the clamped
                                                     pair slid the label along as you
                                                     scrolled, so it sat in the middle of
                                                     the visible remnant and the text
                                                     appeared not to scroll with its span.
                                                     The clip below is what keeps it off
                                                     the lane names.

                                                     Except when it is too long to fit: the
                                                     clip would then take an equal bite off
                                                     each end and leave the middle of a
                                                     word, where starting at the left
                                                     leaves the start of the phrase. A
                                                     label that overflows fills the span
                                                     either way, so the two look the same —
                                                     one is just readable. -->
                                                <text x={fits ? (sx1 + sx2) / 2 : sx1 + 5}
                                                      text-anchor={fits ? 'middle' : 'start'}
                                                      y={y1 + LANE_H - 9} font-size="11"
                                                      fill="#111827" clip-path="url(#{clip})"
                                                      style="pointer-events:none">
                                                    {label}
                                                </text>
                                            {/if}
                                            <title>kit {kit ? kit_label(kit) : span.kit_id} · {kit?.user ?? 'unassigned'}</title>
                                        </g>
                                    {/each}
                                </g>
                            {/each}
                        {/each}
                        </svg>
                    </div>

                    {/if}
                </div>

                {#each blocks.filter((b) => doc_shown(document_key(b))) as block (block.kit_id)}
                    {#if block.arcs.some((a) => a.dangling)}
                        <div class="mt-2 text-sm text-red-700">
                            kit {kit_label(block)}: spans with a missing anchor —
                            {block.arcs.filter((a) => a.dangling)
                                .map((a) => `${a.name} ${a.iid} (${a.beg_iid}→${a.end_iid})`).join(', ')}
                        </div>
                    {/if}
                {/each}
            </div>

            <!-- The structure of one span, which the lanes above can't show.
                 Shut until a span is clicked, so the drawing has the whole width
                 until there is something to put here. -->
            {#if pane_open}
            <div class="w-96 shrink-0 border border-gray-300 rounded p-3">
                <div class="flex items-center justify-between mb-2">
                    <div class="font-medium">Structure</div>
                    <div class="flex gap-2">
                        {#if inspecting}
                            <button class={btn} onclick={() => (selected = null)}>Clear</button>
                        {/if}
                        <button class={btn} onclick={() => (pane_open = false)}>Close</button>
                    </div>
                </div>
                {#if !inspecting}
                    <div class="text-sm text-gray-600">
                        Click a span to see its anchors, its arc node and its labels — and the
                        other spans hanging off the same anchors, which the timeline can't
                        distinguish from spans that merely abut it.
                    </div>
                {:else}
                    {@const arc = inspecting.arc}
                    {@const beg = inspecting.anchors.find((n) => n.iid === arc.beg_iid)}
                    {@const end = inspecting.anchors.find((n) => n.iid === arc.end_iid)}
                    <svg width="340" height={80 + arc.labels.length * 22}>
                        <!-- anchor → arc → anchor, labels hung below the arc -->
                        <line x1="40" y1="30" x2="300" y2="30" stroke={edge(arc.name)} stroke-width="2" />
                        <rect x="118" y="20" width="104" height="20" rx="3"
                              fill={fill(arc.name)} stroke={edge(arc.name)} />
                        <text x="170" y="34" font-size="10" text-anchor="middle">
                            Arc {arc.arc_node_iid ?? arc.iid + 1}
                        </text>
                        <circle cx="40" cy="30" r="9" fill="#fff" stroke="#374151" stroke-width="2" />
                        <circle cx="300" cy="30" r="9" fill="#fff" stroke="#374151" stroke-width="2" />
                        <text x="40" y="15" font-size="10" text-anchor="middle" fill="#374151">{arc.beg_iid}</text>
                        <text x="300" y="15" font-size="10" text-anchor="middle" fill="#374151">{arc.end_iid}</text>
                        <text x="40" y="52" font-size="9" text-anchor="middle" fill="#6b7280">{format_time(beg?.time)}</text>
                        <text x="300" y="52" font-size="9" text-anchor="middle" fill="#6b7280">{format_time(end?.time)}</text>
                        {#each arc.labels as label, i}
                            <line x1="170" y1="40" x2="170" y2={62 + i * 22} stroke="#9ca3af" />
                            <rect x="90" y={62 + i * 22} width="170" height="18" rx="3" fill="#fff" stroke="#9ca3af" />
                            <text x="96" y={75 + i * 22} font-size="10">
                                {label.name} {label.iid}: {String(label.value ?? '').slice(0, 22)}
                            </text>
                        {/each}
                    </svg>

                    <table class="w-full text-xs font-mono mb-3">
                        <tbody>
                            <tr><td class="text-gray-500 pr-2">kit</td>
                                <td class="break-all">{kit_label(inspecting.block)}</td></tr>
                            <tr><td class="text-gray-500 pr-2">arc iid</td>
                                <td>{arc.iid} ({arc.name})</td></tr>
                            <tr><td class="text-gray-500 pr-2">arc_node_iid</td>
                                <td>{arc.arc_node_iid ?? ''}</td></tr>
                            <tr><td class="text-gray-500 pr-2">beg</td>
                                <td>{arc.beg_iid} @ {format_time(arc.beg)}</td></tr>
                            <tr><td class="text-gray-500 pr-2">end</td>
                                <td>{arc.end_iid} @ {format_time(arc.end)}</td></tr>
                        </tbody>
                    </table>

                    <div class="text-sm font-medium mb-1">Labels ({arc.labels.length})</div>
                    <table class="w-full text-xs font-mono mb-3">
                        <tbody>
                            {#each arc.labels as label (label.iid)}
                                <tr>
                                    <td class="text-gray-500 pr-2 align-top">{label.name} {label.iid}</td>
                                    <td class="break-all">{label.value ?? ''}</td>
                                </tr>
                            {:else}
                                <tr><td class="text-gray-500">none — a structural span</td></tr>
                            {/each}
                        </tbody>
                    </table>

                    <div class="text-sm font-medium mb-1">
                        Sharing an anchor ({inspecting.neighbours.length})
                    </div>
                    <table class="w-full text-xs font-mono">
                        <tbody>
                            {#each inspecting.neighbours as n (n.iid)}
                                <tr class="cursor-pointer hover:bg-gray-100"
                                    onclick={() => (selected = { kit_id: inspecting.block.kit_id, iid: n.iid })}>
                                    <td class="pr-2">{n.name} {n.iid}</td>
                                    <td>{n.beg_iid}→{n.end_iid}</td>
                                </tr>
                            {:else}
                                <tr><td class="text-gray-500">none</td></tr>
                            {/each}
                        </tbody>
                    </table>
                {/if}
            </div>
            {/if}
        </div>
    {/if}
</div>
