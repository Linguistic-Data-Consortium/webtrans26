// Spans — { beg, end, docid, text? } in seconds — as features other than the
// transcript hand them around: sound-level segmentation, ASR results, span
// layers (span_layers.svelte.js). Nothing here knows which feature made them.

// Only fill gaps: a proposed span touching an existing segment on the same
// docid is dropped, so running this mid-transcript never makes an overlap.
// Read-only rows are reference captions, not the annotator's segments, and
// don't count.
export function drop_overlapping(segments, existing, docid_of){
    const kept = [];
    let skipped = 0;
    for(const s of segments){
        const docid = docid_of(s);
        const hit = existing.some( (x) => !x.readonly && x.docid == docid
            && x.beg != null && x.end != null && x.beg < s.end && s.beg < x.end );
        if(hit) skipped++;
        else    kept.push(s);
    }
    return { kept, skipped };
}

// What's wrong with a span, or null if nothing is. A span has a docid — the
// channel it's on — and an end after its beginning, both finite seconds from
// the start of the recording.
export function span_problem(s){
    if(!s || typeof s !== 'object') return 'not an object';
    if(typeof s.docid !== 'string' || s.docid === '') return 'no docid';
    if(!Number.isFinite(s.beg) || !Number.isFinite(s.end)) return 'beg and end must be numbers';
    if(s.beg < 0) return 'begins before zero';
    if(s.end <= s.beg) return 'ends before it begins';
    if(s.text != null && typeof s.text !== 'string') return 'text must be a string';
    return null;
}

const round3 = (x) => Math.round(x * 1000) / 1000;

// The stretch a run was bounded to, for a layer's name.
export function stretch_label(span){
    if(!span || (!(span.beg > 0) && span.end === Infinity)) return '';
    return ` · ${round3(span.beg)}–${span.end === Infinity ? 'end' : round3(span.end)} s`;
}

// Rows as xasr_process makes them ({ docid, offset, length, transcript })
// into spans. Anything a span can't be is left out rather than refused: a
// service's zero-length or untimed item is no loss to a preview.
export function rows_to_spans(rows){
    return rows.map( (r) => {
        const s = { beg: round3(r.offset), end: round3(r.offset + r.length), docid: r.docid };
        const t = (r.transcript ?? r.text ?? '').trim();
        if(t) s.text = t;
        return s;
    } ).filter( (s) => span_problem(s) == null );
}

// Segments recognised from a stretch cut out of a recording are timed from
// the stretch's start; this times them from the recording's. To the
// microsecond, as chunks_to_segments rounds them.
export function offset_segments(segments, by){
    const r6 = (x) => Math.round(x * 1e6) / 1e6;
    return segments.map( (s) => ({ ...s, beg: r6(s.beg + by), end: r6(s.end + by) }) );
}

