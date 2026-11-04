// ASR suggestions — experimental, switched on from the Controls toolbar.
//
// While on, the segments just ahead of the annotator are run through the
// in-browser model one at a time, and what it hears is shown in their rows
// (segments.svelte) without being saved: suggestions, not annotations. The
// annotation log only hears of one when its segment is selected while still
// empty — then the suggestion becomes the segment's text, saved the way typed
// text is.
//
// The queue is replaced, not appended to, each time the annotator moves, so
// work goes to what is coming up next rather than to where they used to be. A
// suggestion already made is kept until its segment's times change
// (suggestion_key).

import { local_asr_available } from '../local_asr';
import { transcribe_one } from './segment_asr_run';
import { suggestion_key } from './segment_asr';
import { toast } from 'svelte-sonner';

const STORAGE_KEY = 'asr_preview';

function remembered(){
    try { return localStorage.getItem(STORAGE_KEY) === 'on'; } catch(e){ return false; }
}

export const preview = $state({
    on: false,
    // suggestion_key → { status: 'pending' | 'ready' | 'none' | 'error', text?, message? }
    suggestions: {},
    // Set when the model itself can't be had — a load that failed. Stops the
    // queue, rather than failing the same way once per segment; switching the
    // mode off and on again tries again.
    error: null,
    // What the model is doing, for the toolbar: null, or a phrase.
    stage: null
});

// Read after the page has loaded: local_asr_available needs the window.
export function init_preview(){
    preview.on = remembered() && local_asr_available();
}

export function set_preview(on){
    preview.on = on && local_asr_available();
    preview.error = null;
    said = false;
    if(!preview.on) queue = [];
    // Failures are tried again: switching back on is how the annotator asks.
    for(const [ k, v ] of Object.entries(preview.suggestions)) if(v.status == 'error') delete preview.suggestions[k];
    try { localStorage.setItem(STORAGE_KEY, preview.on ? 'on' : 'off'); } catch(e){}
}

// Suggestions made by a model that has since been replaced aren't that
// model's; forget them so the segments ahead are asked again.
export function forget_suggestions(){
    for(const k of Object.keys(preview.suggestions)) delete preview.suggestions[k];
    queue = [];
    if(preview.on && ctx) want(last_rows, ctx);
}

export function suggestion_for(row){
    return preview.suggestions[suggestion_key(row)] ?? null;
}

let queue = [];
let busy = false;
let ctx = null;
// One report per switch-on. A segment that fails usually means every segment
// will fail for the same reason, and a toast each time is unreadable — but
// saying nothing at all is worse: before this, a failing segment showed an
// ellipsis that vanished and left the row empty, with the reason only in a
// console nobody opens.
let said = false;
let last_rows = [];

// The segments to have suggestions for, nearest first. `context` is what
// transcribe_one needs: { ldc, docids, source_uid_channels }.
export function want(rows, context){
    ctx = context;
    last_rows = rows;
    queue = rows.filter( (r) => !preview.suggestions[suggestion_key(r)] );
    pump();
}

function stage(m){
    if(m?.stage == 'transcribing') preview.stage = null;
    else if(m?.stage)               preview.stage = 'Loading the speech model…';
}

async function pump(){
    if(busy) return;
    busy = true;
    try {
        while(preview.on && !preview.error && queue.length){
            const row = queue.shift();
            const k = suggestion_key(row);
            if(preview.suggestions[k]) continue;
            preview.suggestions[k] = { status: 'pending' };
            try {
                const text = await transcribe_one(row, { ...ctx, onstage: stage });
                preview.suggestions[k] = text ? { status: 'ready', text } : { status: 'none' };
            }
            catch(e){
                const message = e?.message || String(e);
                // Ended by someone else — a Services 7 run cancelled, which
                // closes the shared session. Nothing wrong with this segment;
                // forget it so it's asked about again.
                if(message == 'cancelled'){ delete preview.suggestions[k]; continue; }
                preview.suggestions[k] = { status: 'error', message };
                // The model not loading isn't this segment's fault, and will
                // happen to every other one too: stop, and say so once.
                if(/loading the model|worker|no available backend|cannot run/i.test(message)){
                    preview.error = message;
                    toast.error(`ASR suggestions stopped: ${message}`, { duration: Infinity });
                    said = true;
                }
                else if(!said){
                    // Anything else — a segment whose audio could not be read
                    // or decoded. The run continues, because one bad stretch
                    // should not end the mode, but the first reason is worth
                    // showing: the alternative is rows that flash and stay
                    // blank.
                    said = true;
                    toast.error(`ASR suggestion failed: ${message}`, { duration: Infinity });
                }
            }
        }
    }
    finally {
        busy = false;
        preview.stage = null;
    }
}
