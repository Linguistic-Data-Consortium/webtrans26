// The write path, over the graph rows.
//
// Every edit the tool makes becomes a message to /annotations — `add` with a
// group string, `change` with a node and a value, `delete` with a node. Those
// messages are the record: the server replays them to rebuild the tree, and
// Kit#graph_projection folds the result into anchors, spans and labels. So the
// same messages, applied to the rows here, keep the client's graph current
// without re-deriving it from the node layer after every keystroke.
//
// Pure: each function takes the rows and returns new ones, or null when the
// message doesn't touch the tree (`done`, `broken`, `skip`). The caller decides
// what to do with the result — which keeps this testable against the fold in
// graph_from_payload.js, whose output it has to match exactly.

const number = (x) => (x == null || x === '' ? null : Number(x));

// "5:SegmentListItem,6:Arc,7:Text,8:Speaker" — what addf allocated and what the
// server will log verbatim. The first pair is the list item; the rest are its
// children, and which children they are says what kind of group this is.
function parse_group(value){
    const text = (value && typeof value === 'object' ? value.value : value) || '';
    return String(text).split(',').map( (pair) => {
        const [ iid, name ] = pair.split(':');
        return { iid: Number(iid), name: name };
    } ).filter( (x) => x.name && !Number.isNaN(x.iid) );
}

// The other end of parse_group: build the group string for a new list item and
// its children, taking iids from where the client left off.
//
// This is the whole of what a new group is — the class def says which children a
// SegmentList item has, the counter says which iids they get, and the string is
// what the server logs. It lives here rather than in work/other.js's addf so
// that making a segment doesn't have to begin in the node layer.
//
// The counter is not reset or reused: iids are handed out once per tree, and
// last_iid is where the payload said to resume.
export function new_group(list, classes, last_iid){
    const children = (classes && classes[list] && classes[list].children) || [];
    let iid = Number(last_iid) || 0;
    const pairs = [ [ ++iid, `${list}Item` ] ];
    for(const child of children) pairs.push([ ++iid, child ]);
    return { value: pairs.map( ([ i, name ]) => `${i}:${name}` ).join(','), last_iid: iid };
}

const by_iid = (a, b) => a.iid - b.iid;
const by_arc = (a, b) => a.arc_iid - b.arc_iid || a.iid - b.iid;

function apply_add(graph, value){
    const group = parse_group(value);
    if(group.length < 2) return null;
    const [ item, ...children ] = group;

    // "1:NListItem,2:N" — a time anchor. It has no time until a change arrives.
    const n = children.find( (c) => c.name === 'N' );
    if(n){
        return {
            ...graph,
            nodes: [ ...graph.nodes, { iid: item.iid, n_iid: n.iid, docid: null, time: null } ].sort(by_iid)
        };
    }

    // Everything else is a span with its labels, all of them empty so far.
    const arc = children.find( (c) => c.name === 'Arc' );
    return {
        ...graph,
        arcs: [ ...graph.arcs, {
            iid: item.iid,
            name: item.name,
            arc_node_iid: arc ? arc.iid : null,
            beg_iid: null,
            end_iid: null
        } ].sort(by_iid),
        labels: [ ...graph.labels, ...children
            .filter( (c) => c.name !== 'Arc' )
            .map( (c) => ({ iid: c.iid, arc_iid: item.iid, name: c.name, value: '' }) )
        ].sort(by_arc)
    };
}

// A change names a child, and which child it is says what it means: the N of an
// anchor carries the time, the Arc of a span carries the two anchors it runs
// between, and anything else is a label.
function apply_change(graph, node, value){
    const iid = Number(node);
    // Read the value exactly as the fold reads it off the node's store: whatever
    // was set, asked for .value / .beg / .docid. A message carrying something
    // else shaped ends up empty here for the same reason it does there.
    const v = value == null ? {} : value;

    if(graph.nodes.some( (a) => a.n_iid === iid )){
        return {
            ...graph,
            nodes: graph.nodes.map( (a) => (a.n_iid === iid
                ? { ...a, docid: v.docid == null ? null : v.docid, time: number(v.beg) }
                : a) )
        };
    }
    if(graph.arcs.some( (a) => a.arc_node_iid === iid )){
        return {
            ...graph,
            arcs: graph.arcs.map( (a) => (a.arc_node_iid === iid
                ? { ...a, beg_iid: number(v.beg), end_iid: number(v.end) }
                : a) )
        };
    }
    if(graph.labels.some( (l) => l.iid === iid )){
        return {
            ...graph,
            labels: graph.labels.map( (l) => (l.iid === iid
                ? { ...l, value: v.value == null ? null : v.value }
                : l) )
        };
    }
    return null;
}

// Deletes name the list item. A span takes its labels with it; an anchor just
// goes, and any span still pointing at it is left without that time — the same
// state as a span whose anchor hasn't been placed yet.
function apply_delete(graph, node){
    const iid = Number(node);
    if(graph.nodes.some( (a) => a.iid === iid )){
        return { ...graph, nodes: graph.nodes.filter( (a) => a.iid !== iid ) };
    }
    if(graph.arcs.some( (a) => a.iid === iid )){
        return {
            ...graph,
            arcs: graph.arcs.filter( (a) => a.iid !== iid ),
            labels: graph.labels.filter( (l) => l.arc_iid !== iid )
        };
    }
    return null;
}

// ── the batched path ─────────────────────────────────────────────────────────
//
// apply_message above is pure: it returns a new graph. That is what the rune
// needs in order to see a change, and what lets graph_write.test.ts hold the
// result against a fresh fold. It is also the right shape for a keystroke.
//
// It is the wrong shape for a hundred of them. Per message it scans a collection
// to find the row (`.some`), then copies that whole collection (`.map`), and an
// `add` sorts afterwards — so a whole-transcript operation cost
// O(messages x rows), with a sort per added row on top. A thousand-segment ASR
// run re-sorted a growing array a thousand times.
//
// During such an operation nothing renders — the progress panel is up and the
// fold is deferred — so there is no reason to produce the intermediate graphs at
// all. One copy at the start, O(1) per message, one fresh object at the end, and
// the rune sees a single change.
//
// Rows are copied when touched rather than mutated, so the graph handed to
// begin_batch is left exactly as it was. Nothing should be reading it, but a
// write path that quietly edits the state it was given is a bad thing to leave
// lying around.
function index_by(rows, key){
    const m = new Map();
    rows.forEach( (r, i) => { if(r[key] != null) m.set(r[key], i); } );
    return m;
}

export function begin_batch(graph){
    const nodes = [ ...((graph && graph.nodes) || []) ];
    const arcs = [ ...((graph && graph.arcs) || []) ];
    const labels = [ ...((graph && graph.labels) || []) ];
    return {
        nodes, arcs, labels,
        // iid -> position, so finding a row is a lookup rather than a scan. By
        // position because a touched row is replaced with a copy.
        node_by_n: index_by(nodes, 'n_iid'),
        node_by_iid: index_by(nodes, 'iid'),
        arc_by_node: index_by(arcs, 'arc_node_iid'),
        arc_by_iid: index_by(arcs, 'iid'),
        label_by_iid: index_by(labels, 'iid'),
        // Deletes mark rather than splice: removing from the middle is O(n), and
        // one compaction at the end does the same work once.
        dead: { nodes: new Set(), arcs: new Set(), labels: new Set() },
        // Whether anything landed, and whether the order needs restoring.
        changed: false,
        unsorted: false
    };
}

// Same decisions as apply_add/apply_change/apply_delete, against the working set.
// Returns true when the message touched the rows, matching apply_message's
// null-means-nothing-happened contract.
export function apply_batched(b, message, node, value){
    if(message === 'add')    return batched_add(b, value);
    if(message === 'change') return batched_change(b, Number(node), value);
    if(message === 'delete') return batched_delete(b, Number(node));
    return false;
}

function batched_add(b, value){
    const group = parse_group(value);
    if(group.length < 2) return false;
    const [ item, ...children ] = group;

    const n = children.find( (c) => c.name === 'N' );
    if(n){
        b.node_by_iid.set(item.iid, b.nodes.length);
        b.node_by_n.set(n.iid, b.nodes.length);
        b.nodes.push({ iid: item.iid, n_iid: n.iid, docid: null, time: null });
        b.changed = b.unsorted = true;
        return true;
    }

    const arc = children.find( (c) => c.name === 'Arc' );
    b.arc_by_iid.set(item.iid, b.arcs.length);
    if(arc) b.arc_by_node.set(arc.iid, b.arcs.length);
    b.arcs.push({
        iid: item.iid, name: item.name,
        arc_node_iid: arc ? arc.iid : null, beg_iid: null, end_iid: null
    });
    for(const c of children){
        if(c.name === 'Arc') continue;
        b.label_by_iid.set(c.iid, b.labels.length);
        b.labels.push({ iid: c.iid, arc_iid: item.iid, name: c.name, value: '' });
    }
    b.changed = b.unsorted = true;
    return true;
}

function batched_change(b, iid, value){
    const v = value == null ? {} : value;

    let i = b.node_by_n.get(iid);
    if(i != null && !b.dead.nodes.has(i)){
        b.nodes[i] = { ...b.nodes[i], docid: v.docid == null ? null : v.docid, time: number(v.beg) };
        b.changed = true;
        return true;
    }
    i = b.arc_by_node.get(iid);
    if(i != null && !b.dead.arcs.has(i)){
        b.arcs[i] = { ...b.arcs[i], beg_iid: number(v.beg), end_iid: number(v.end) };
        b.changed = true;
        return true;
    }
    i = b.label_by_iid.get(iid);
    if(i != null && !b.dead.labels.has(i)){
        b.labels[i] = { ...b.labels[i], value: v.value == null ? null : v.value };
        b.changed = true;
        return true;
    }
    return false;
}

// Deletes name the list item. A span takes its labels with it; an anchor just
// goes, and any span still pointing at it is left without that time — the same
// state as a span whose anchor hasn't been placed yet.
function batched_delete(b, iid){
    let i = b.node_by_iid.get(iid);
    if(i != null && !b.dead.nodes.has(i)){
        b.dead.nodes.add(i);
        b.changed = true;
        return true;
    }
    i = b.arc_by_iid.get(iid);
    if(i != null && !b.dead.arcs.has(i)){
        b.dead.arcs.add(i);
        // The span's labels go with it. Walked rather than indexed: a span has a
        // handful of labels and arc_iid is not unique, so there is nothing to
        // look up.
        b.labels.forEach( (l, j) => { if(l && l.arc_iid === iid) b.dead.labels.add(j); } );
        b.changed = true;
        return true;
    }
    return false;
}

// One fresh object, so the rune sees exactly one change. Null when nothing
// landed, matching apply_message.
export function end_batch(b){
    if(!b.changed) return null;
    const keep = (rows, dead) => (dead.size ? rows.filter( (_, i) => !dead.has(i) ) : rows);
    const nodes = keep(b.nodes, b.dead.nodes);
    const arcs = keep(b.arcs, b.dead.arcs);
    const labels = keep(b.labels, b.dead.labels);
    // Appends went on the end; the pure path sorted after each one. Once here.
    if(b.unsorted){
        nodes.sort(by_iid);
        arcs.sort(by_iid);
        labels.sort(by_arc);
    }
    return { nodes, arcs, labels };
}

export function apply_message(graph, message, node, value){
    const rows = {
        nodes: (graph && graph.nodes) || [],
        arcs: (graph && graph.arcs) || [],
        labels: (graph && graph.labels) || []
    };
    if(message === 'add')    return apply_add(rows, value);
    if(message === 'change') return apply_change(rows, node, value);
    if(message === 'delete') return apply_delete(rows, node);
    return null;
}

// Does the applied graph still say what a fresh fold of the node layer says?
//
// Returns null when they agree, or a short description of the first few
// disagreements. Values are normalised first: a label that has never been set
// reads as null through the payload and '' through the stores, and times arrive
// as both numbers and numeric strings — neither is a disagreement.
export function graph_difference(applied, folded){
    const text = (x) => (x == null ? '' : String(x));
    const rows = {
        nodes: (g) => (g.nodes || []).map( (n) => `anchor ${n.iid}/${n.n_iid} ${text(n.docid)} ${text(number(n.time))}` ),
        arcs: (g) => (g.arcs || []).map( (a) => `arc ${a.iid} ${a.name} ${text(a.arc_node_iid)} ${text(number(a.beg_iid))}->${text(number(a.end_iid))}` ),
        labels: (g) => (g.labels || []).map( (l) => `label ${l.iid} on ${l.arc_iid} ${l.name}=${text(l.value)}` )
    };

    const differences = [];
    for(const kind of [ 'nodes', 'arcs', 'labels' ]){
        const mine = rows[kind](applied).sort();
        const theirs = rows[kind](folded).sort();
        for(const row of mine) if(!theirs.includes(row)) differences.push(`applied only: ${row}`);
        for(const row of theirs) if(!mine.includes(row)) differences.push(`folded only: ${row}`);
    }
    return differences.length ? differences.slice(0, 4).join('; ') : null;
}

export default apply_message;
