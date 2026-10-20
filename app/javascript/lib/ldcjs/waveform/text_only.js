// transcribe_text_only: this kit's segments came from an imported graph, so
// the operations that would change them don't run. Typing does, comments do,
// and closing the kit does.
//
// Asked per operation, at the function each operation goes through. It was
// once asked of the messages instead — which reads every message rather than
// every feature, and 'done' is a message, so closing a kit was refused along
// with splitting one.
//
// Its own module because it has no dependencies and both modification1.js and
// waveform.svelte need it; importing either from the other's tests drags in
// the whole tool.
let locked = false;

// Called once the imported segments are in place (waveform.svelte's
// load_imported_transcript). Nothing turns it off: a kit is locked for as long
// as the page is open.
export function lock_text_only(){
    locked = true;
}

export function text_only(){
    return locked;
}

// True when the operation may not run, and says so in the console — the
// gestures are gone from the UI, so anything reaching here came by a route
// that should have been closed off, and that's worth seeing.
export function text_only_refuses(operation){
    if(!locked) return false;
    console.warn(`[text_only] ${operation}: this kit transcribes an imported transcript`);
    return true;
}

// Tests run against a module that remembers; let them start clean.
export function reset_text_only(){
    locked = false;
}
