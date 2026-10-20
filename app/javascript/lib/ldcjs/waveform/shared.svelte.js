const activeo = $state({
    docid: null,
    channel: 0,
    wave_display_offset: 0,
    wave_display_length: 0,
    wave_selection_offset: null,
    wave_selection_length: 0,
    // wave_selection_end: null,
    underline: null,
    active: null,
    last_active_segment: null
});

// const s = {
//   wave_selection_offset: null,
//   wave_selection_length: 0,
//   wave_selection_end: null
// };

const urls = {};
const cache = {};
const scache = {};
const cache2 = {};
const srcache = {};

const sourceso = {
    srcs: {}
};

const sourcesor = $state({
    srcs: {}
});

// Reference transcript text for the "blanks" import mode. Each reference
// segment's text and time span is stashed here, so the segment list can display
// it above the segments it lines up with — instead of injecting a separate
// read-only segment row. The match criterion is time-span *overlap*, so a
// caption stays put even if the annotator nudges the segment's extent (as long
// as it still overlaps the reference).
const reference_text = $state({ segments: [] });

// Register a reference caption spanning [beg, end].
function set_reference_text(beg, end, text){
    reference_text.segments.push({ beg, end, text });
}

// Reference text to display above a segment spanning [beg, end]: the text of
// every reference whose time span overlaps it, in time order. undefined when
// nothing overlaps. Touching endpoints (one ends exactly where the next begins)
// do not count as overlap.
function get_reference_text(beg, end){
    const hits = reference_text.segments
        .filter( (s) => s.beg < end && s.end > beg )
        .sort( (a, b) => a.beg - b.beg );
    if(!hits.length) return undefined;
    return hits.map( (s) => s.text ).join(' ');
}

// Drop all stored references (e.g. before a fresh import / reload).
function clear_reference_text(){
    reference_text.segments = [];
}

export {
    activeo,
    urls,
    cache,
    scache,
    cache2,
    srcache,
    sourceso,
    sourcesor,
    reference_text,
    set_reference_text,
    get_reference_text,
    clear_reference_text
}
