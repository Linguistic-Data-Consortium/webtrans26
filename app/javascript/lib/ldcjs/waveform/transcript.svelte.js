// The transcript the waveform derives and the views render: one row per
// segment, plus the rows that have no time yet and the section list.
//
// Runes rather than svelte/store — same pattern as shared.svelte.js. It's one
// exported object because an exported `$state` *primitive* can't be reassigned
// by importers and have them see it; fields on an exported object can.
//
// Plain .js files can still write to these (the proxy notifies either way);
// only reads inside components are reactive, which is all anyone needs.
export const transcript = $state({
    segments: [],
    undefined_segments: [],
    sections: [],
    // Remarks about stretches of audio, in their own list. Deliberately not
    // part of `segments`: that array is what create_transcript writes, and a
    // comment is not transcript.
    comments: []
});

// Re-publishes the list after a row object was mutated in place rather than
// replaced — what `segments.update(x => x)` used to do by re-notifying
// subscribers. A rune tracks the array, so hand it a new one.
export function touch_segments(){
    transcript.segments = [ ...transcript.segments ];
}

// The same tree as `transcript`, but as the annotation graph describes it:
// anchors, spans and labels. Unfolded from the kit payload by
// graph_from_payload.js at load, so it's here from the moment the page renders
// — no snapshot, no round trip, and nothing added to the wire format.
// graph_transcript.js can flatten these rows into a transcript, but nothing
// renders from it now that the Graph panel shows the rows themselves.
//
// `source` says which rows are in hand: 'payload' is the fold of what the kit
// loaded with, 'snapshot' what /kits/graph read back out of the tables.
export const graph = $state({ nodes: [], arcs: [], labels: [], source: null });

export function set_graph(x, source = 'payload'){
    graph.nodes = (x && x.nodes) || [];
    graph.arcs = (x && x.arcs) || [];
    graph.labels = (x && x.labels) || [];
    graph.source = x ? source : null;
}
