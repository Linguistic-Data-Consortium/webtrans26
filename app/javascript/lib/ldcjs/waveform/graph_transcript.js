// Builds the flat transcript straight out of the graph projection —
// graph_nodes (time anchors), graph_arcs (spans), graph_labels (what's said
// about a span) — with no per-node stores, subscriptions or mutation in
// between.
//
// Plain functions rather than runes: a component wraps them in $derived
// (`const rows = $derived(graph_segments(graph))`), which keeps the reactivity
// at the consumer and leaves these testable on their own. Exported derived
// state isn't allowed anyway — Svelte tells you to export a function.

const times_by_anchor = (graph) =>
    new Map((graph.nodes || []).map( (n) => [ n.iid, n.time == null ? null : Number(n.time) ] ));

const labels_by_arc = (graph) => {
    const map = new Map();
    for(const label of graph.labels || []){
        if(!map.has(label.arc_iid)) map.set(label.arc_iid, []);
        map.get(label.arc_iid).push(label);
    }
    return map;
};

const label_value = (labels, name) => {
    const found = (labels || []).find( (l) => l.name === name );
    return found && found.value != null ? found.value : '';
};

// One row per arc of the given kind: its span resolved through the anchors it
// points at, plus its labels.
function graph_rows(graph, name){
    const times = times_by_anchor(graph);
    const labels = labels_by_arc(graph);
    return (graph.arcs || [])
        .filter( (arc) => arc.name === name )
        .map( (arc) => {
            const own = labels.get(arc.iid);
            return {
                iid: arc.iid,
                arc_node_iid: arc.arc_node_iid,
                beg: times.has(arc.beg_iid) ? times.get(arc.beg_iid) : null,
                end: times.has(arc.end_iid) ? times.get(arc.end_iid) : null,
                text: label_value(own, 'Text'),
                speaker: label_value(own, 'Speaker'),
                label: label_value(own, 'Name'),
            };
        } );
}

// Rows with a time, in time order — what the transcript shows.
function graph_segments(graph){
    return graph_rows(graph, 'SegmentListItem')
        .filter( (r) => r.beg != null && r.end != null )
        .sort( (x, y) => x.beg - y.beg || x.iid - y.iid );
}

// Rows whose anchors carry no time yet: the same thing undefined_segments
// holds in the live transcript.
function graph_undefined_segments(graph){
    return graph_rows(graph, 'SegmentListItem')
        .filter( (r) => r.beg == null || r.end == null )
        .map( (r) => r.iid );
}

function graph_sections(graph){
    return graph_rows(graph, 'SectionListItem').sort( (x, y) => (x.beg ?? 0) - (y.beg ?? 0) );
}

// Does the derived transcript say the same thing as the live one?
//
// Compared by iid, since that's what both sides carry and it survives
// re-sorting. Reference rows (the blanks import) and other client-only rows
// have no graph counterpart, so they're skipped rather than reported. Times
// come from a decimal column on one side and a float on the other, so they're
// compared with a tolerance.
function compare_segments(live, derived, tolerance = 0.0005){
    const text = (x) => (x == null ? '' : String(x));
    const close = (a, b) => a != null && b != null && Math.abs(Number(a) - Number(b)) <= tolerance;

    const live_rows = (live || []).filter( (r) => !r.readonly && !r.virtual && r.iid != null );
    const by_iid = new Map((derived || []).map( (r) => [ r.iid, r ] ));

    const only_live = [];
    const differing = [];
    for(const row of live_rows){
        const other = by_iid.get(row.iid);
        if(!other){ only_live.push(row.iid); continue; }
        const fields = [];
        if(!close(row.beg, other.beg)) fields.push('beg');
        if(!close(row.end, other.end)) fields.push('end');
        if(text(row.text) !== text(other.text)) fields.push('text');
        if(text(row.speaker) !== text(other.speaker)) fields.push('speaker');
        if(fields.length) differing.push({ iid: row.iid, fields });
    }
    const live_iids = new Set(live_rows.map( (r) => r.iid ));
    const only_derived = (derived || []).map( (r) => r.iid ).filter( (iid) => !live_iids.has(iid) );

    return {
        matches: only_live.length === 0 && only_derived.length === 0 && differing.length === 0,
        compared: live_rows.length,
        only_live,
        only_derived,
        differing,
    };
}

export { graph_rows, graph_segments, graph_undefined_segments, graph_sections, compare_segments };
