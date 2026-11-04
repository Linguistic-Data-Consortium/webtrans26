// Pure helpers for span layers (span_layers.svelte.js, PreviewLane.svelte).

// Where a layer's spans fall in the waveform window: [ { i, left, width } ]
// in pixels, only those that show, clipped to the window's edges. `i` is the
// span's index in `segments`. A span narrower than a pixel is drawn one pixel
// wide, so a short blip is still there to see and click.
export function bands_in_window(segments, offset, length, width){
    if(!(length > 0) || !(width > 0)) return [];
    const px = width / length;
    const out = [];
    segments.forEach( (s, i) => {
        const beg = Math.max(s.beg, offset);
        const end = Math.min(s.end, offset + length);
        if(end <= beg) return;
        const left = (beg - offset) * px;
        out.push({ i, left, width: Math.max(1, (end - beg) * px) });
    } );
    return out;
}

// A layer's spans by channel, in the order the kit lists its docids: one bar
// per channel in the lane. [ { docid, segments: [ { ...span, i } ] } ]
export function by_channel(segments, docids){
    const groups = new Map();
    segments.forEach( (s, i) => {
        if(!groups.has(s.docid)) groups.set(s.docid, []);
        groups.get(s.docid).push({ ...s, i });
    } );
    const rank = (d) => { const k = docids.indexOf(d); return k < 0 ? Infinity : k; };
    return [ ...groups.entries() ]
        .sort( (a, b) => rank(a[0]) - rank(b[0]) )
        .map( ([ docid, segs ]) => ({ docid, segments: segs }) );
}

// Distinct colours for layers, reused only once all are taken.
export const PALETTE = Object.freeze([ '#7c3aed', '#0891b2', '#d97706', '#16a34a', '#db2777', '#4f46e5', '#65a30d', '#dc2626' ]);

export function next_color(layers){
    const used = new Set(layers.map( (l) => l.color ));
    return PALETTE.find( (c) => !used.has(c) ) ?? PALETTE[layers.length % PALETTE.length];
}
