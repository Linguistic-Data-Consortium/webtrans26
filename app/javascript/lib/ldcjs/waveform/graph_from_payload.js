// Unfolds the kit payload into the annotation graph: time anchors, the spans
// between them, and the labels on those spans.
//
// The payload is the tree folded flat — a list of nodes, each pointing at a
// value — because that's the shape the editor's per-node stores consume. The
// structure is still in there: every add message left a level-2 list item with
// its level-3 children, and which children it has says what the group is. A
// group with an N is a time anchor; anything else spans two anchors, with one
// child per thing said about that span.
//
// This is Kit#graph_projection written again on this side of the wire, over the
// same payload the server has always sent — nothing was added to it for this.
// Values are found through each node's annotation_id, which is how both payload
// routes key them (the log by annotation id, the graph shape by the node's own
// iid); the fold doesn't care which.
//
// Two ways in, one fold: graph_from_payload for the tree as it arrived, and
// graph_from_nodes for the live node layer, which is the same tree with the
// annotator's edits in it. The transcript is rendered from the second.

import { get } from 'svelte/store';

function value_map(payload){
    return new Map(((payload && payload.node_values) || []).map( (v) => [ v.id, v ] ));
}

// The payload as it arrives: values are a separate list, reached through each
// node's annotation_id.
export function graph_from_payload(payload){
    const values = value_map(payload);
    // A child that was never changed points at annotation 0, the placeholder —
    // it has no value yet, which reads the same as no entry.
    return fold((payload && payload.nodes) || [], (node) => values.get(node.annotation_id) || {});
}

// The live node layer (ldc.nodes) after the payload has been unpacked into it:
// same tree, but each node's value lives in its own node_value store. Folding
// this rather than the payload gives the graph as it stands now, edits
// included.
//
// Read the store itself, not the `value` field mirroring it. svelte/store
// queues subscriber callbacks when one store is set during another store's
// notification, so that mirror — written by a subscriber like any other — can
// still hold the previous value while the transcript is being rebuilt. A burst
// of changes is exactly when a segment is created (two anchors, an arc, then
// its labels), so folding the mirror gets a tree with no times in it. `get`
// reads the store synchronously and is never behind.
export function graph_from_nodes(node_map){
    const nodes = node_map ? Array.from(node_map.values()) : [];
    return fold(nodes, (node) => (node && node.node_value ? get(node.node_value) : node && node.value) || {});
}

function fold(nodes, value_of){
    // Level-2 list items are their own group; level-3 children name their
    // parent. Grouping this way rather than by level keeps a child whose list
    // item was deleted out from under it from inventing a group of its own.
    const groups = new Map();
    for(const node of nodes){
        const key = node.parent_iid == null ? node.iid : node.parent_iid;
        if(!groups.has(key)) groups.set(key, []);
        groups.get(key).push(node);
    }

    const anchors = [];
    const arcs = [];
    const labels = [];

    for(const [ iid, members ] of groups){
        const item = members.find( (m) => m.iid === iid );
        if(!item) continue; // orphaned children: no list item, no group
        const children = members.filter( (m) => m.iid !== iid );
        const child = (name) => children.find( (c) => c.name === name );

        const n = child('N');
        if(n){
            // "10:NListItem,11:N" — the N carries the docid and the one time.
            const v = value_of(n);
            anchors.push({
                iid: iid,
                n_iid: n.iid,
                docid: v.docid == null ? null : v.docid,
                time: v.beg == null ? null : Number(v.beg)
            });
            continue;
        }

        // Everything else spans two anchors, named by the Arc child...
        const arc = child('Arc');
        const v = value_of(arc);
        arcs.push({
            iid: iid,
            name: item.name,
            arc_node_iid: arc ? arc.iid : null,
            beg_iid: v.beg == null ? null : Number(v.beg),
            end_iid: v.end == null ? null : Number(v.end)
        });
        // ...and every other child says something about that span: Text and
        // Speaker for a segment, Name for a section, whatever the class def
        // declares for anything else. A label's arc_iid is the arc's own iid —
        // the list item — not the arc's arc_node_iid.
        for(const c of children){
            if(c.name === 'Arc') continue;
            const cv = value_of(c);
            labels.push({
                iid: c.iid,
                arc_iid: iid,
                name: c.name,
                value: cv.value == null ? null : cv.value
            });
        }
    }

    anchors.sort( (a, b) => a.iid - b.iid );
    arcs.sort( (a, b) => a.iid - b.iid );
    labels.sort( (a, b) => a.arc_iid - b.arc_iid || a.iid - b.iid );

    return { nodes: anchors, arcs: arcs, labels: labels };
}

export default graph_from_payload;
