// Progress for an operation that rewrites the whole transcript.
//
// These operations all have the same problem. Each one issues its changes in
// batches, every batch is a server round trip, and the transcript re-renders
// between them — so a long run shows rows appearing or vanishing in front of
// the annotator, with no way to tell a run still going from one that has
// stalled or finished. The segment list hides itself while one is in flight and
// shows what is happening instead (segments.svelte).
//
// The ASR add loop had this first, reading asr.svelte.js's own fields. It isn't
// specific to ASR: deleting every segment and replacing a speaker label
// everywhere are the same shape and want the same panel. So the state lives
// here, operation-agnostic, and each operation reports into it.
//
//     bulk_start('Deleting segments', all.length);
//     ... per batch: bulk_done(j);
//     ... at the end: bulk_end();
//
// `total` of 0 means the size isn't known yet — a service call that hasn't
// answered, say. The panel reports that as an indeterminate "…" rather than a
// bar pinned at zero, which reads as stuck.
//
// What reports, and what doesn't. The panel earns its place where an operation
// takes several round trips, and all three now use the same batch size, so the
// progress they report means the same thing:
//
//     ASR add                     asr.svelte.js        xasrrr
//     delete every segment        modification1.js     delete_batch
//     replace a speaker label     modification1.js     change_batch
//
// delete_all2 (the stereo/by-docid delete) and delete_all_sections issue every
// message and submit once, so they finish in a single trip and a panel would
// flash for one frame. Not an omission.
//
// One consequence of a batch this size: an operation over fewer items than one
// batch reports nothing until it finishes. That is deliberate — see the count
// guard in segments.svelte — and it is why the label matters as much as the bar.
//
// One at a time, deliberately: the transcript is hidden while a run goes, so
// two concurrent runs have no coherent display, and nothing issues them
// concurrently. A second bulk_start simply replaces the first.
// How many messages go out per round trip. Shared so the three batched
// operations agree: a progress step means the same number of items everywhere,
// and there is one number to change.
//
// Was 10 for deletes and 100 for ASR, with the speaker replace unbatched at one
// round trip per row — so the same panel reported three different things.
const BATCH_SIZE = 100;

const bulko = $state({
    // What is happening, as a phrase the panel can show: 'Running ASR',
    // 'Deleting segments'. null means nothing is in flight.
    label: null,
    // Items confirmed done. Batched operations advance this per batch, so it
    // moves in steps rather than smoothly.
    done: 0,
    // How many there are in total, or 0 if that isn't known yet.
    total: 0
});

// Hand the browser a chance to paint before starting work.
//
// bulk_start only sets state. Nothing is drawn until the current task yields,
// and the operations that call it go straight into their first batch — around a
// hundred immutable graph updates, each one scanning and copying the row
// collection. So the panel announcing the work appeared *after* the first
// batch of it, which on a long transcript reads as the app having hung at the
// moment the annotator asked for something.
//
// A frame rather than a timeout: requestAnimationFrame is the callback that
// runs after a paint, which is exactly the guarantee wanted. Falls through to a
// direct call where there is no frame loop, so a test or a non-browser caller
// still completes.
function bulk_after_paint(f){
    if(typeof requestAnimationFrame === 'function') requestAnimationFrame(f);
    else f();
}

function bulk_start(label, total = 0){
    bulko.label = label;
    bulko.done = 0;
    bulko.total = total;
}

// The count becoming known part-way through, and the label usually changing
// with it — 'Running ASR' has no total until the service answers, and what
// follows is 'Loading segments' with one.
function bulk_total(total, label = null){
    bulko.total = total;
    if(label) bulko.label = label;
}

function bulk_done(n){
    // The ASR loop reports -1 before its first batch; clamp so the panel never
    // shows a negative count, and never more than the total.
    const max = bulko.total || n;
    bulko.done = Math.min(Math.max(n, 0), max);
}

// Always call this, including on the paths that bail out early — a refused
// operation that leaves the label set hides the transcript for good.
function bulk_end(){
    bulko.label = null;
    bulko.done = 0;
    bulko.total = 0;
}

export { BATCH_SIZE, bulko, bulk_start, bulk_after_paint, bulk_total, bulk_done, bulk_end };
