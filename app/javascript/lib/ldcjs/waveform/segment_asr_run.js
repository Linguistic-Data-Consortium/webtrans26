// segment_asr.js with the real reading, decoding and recognising wired in.

import { open_audio } from './energy_run';
import { open_local_asr_session, decode_to_samples, asr_model, run_language, run_local_asr } from '../local_asr';
import { source_for, segment_bytes, transcribe_rows } from './segment_asr';
import { offset_segments } from './spans';

// One session for the page, kept between runs. Opening one means a new Worker
// and the model built again — from the browser's cache, so it reports every
// file "downloaded" at once, but building the session and compiling for
// WebGPU or WASM still takes seconds. Paid per keypress, that made every
// single segment slow. Kept, only the first pays.
//
// Closed after IDLE_MS without use, since the model holds a few hundred MB,
// and on cancel; the next request opens a fresh one.
const IDLE_MS = 5 * 60 * 1000;
let shared = null;      // Promise of a session
let shared_model = null;
let idle_timer = null;
let on_stage = null;    // the current run's progress listener

function session(){
    clearTimeout(idle_timer);
    // A session runs the model and language it was opened with. Another one
    // chosen since means a fresh session, not the old one kept warm.
    const key = `${asr_model()}|${run_language() ?? ''}`;
    if(shared && shared_model !== key) close_shared();
    if(!shared){
        const p = open_local_asr_session({ onprogress: (m) => on_stage?.(m) });
        shared = p;
        shared_model = key;
        // A session that failed to open isn't kept, or every later request
        // would get the same failure.
        p.catch( () => { if(shared === p) shared = null; } );
    }
    return shared;
}

function release(){
    clearTimeout(idle_timer);
    idle_timer = setTimeout(close_shared, IDLE_MS);
}

// Also for the resources dialog: after the model's files are deleted, or
// another model is chosen, nothing should keep the old one in memory.
export function close_asr_session(){ close_shared(); }

function close_shared(){
    clearTimeout(idle_timer);
    const p = shared;
    shared = null;
    p?.then( (s) => s.close(), () => {} );
}

// Each recording opened (its url resolved, its header read) once and reused
// for every segment read from it — for a while: an S3 recording's url is
// presigned and expires, so after OPEN_FOR_MS it is opened, and signed, again.
const OPEN_FOR_MS = 10 * 60 * 1000;
const opened = new Map();   // source_uid → { p, at }
function audio_of(source_uid, ldc){
    const o = opened.get(source_uid);
    if(o && Date.now() - o.at < OPEN_FOR_MS) return o.p;
    const p = open_audio(source_uid, ldc);
    opened.set(source_uid, { p, at: Date.now() });
    p.catch( () => { if(opened.get(source_uid)?.p === p) opened.delete(source_uid); } );
    return p;
}

async function samples_for(row, { ldc, docids, source_uid_channels }){
    const { source_uid, channel } = source_for(row.docid, docids, source_uid_channels);
    const bytes = await segment_bytes(await audio_of(source_uid, ldc), row.beg, row.end);
    return (await decode_to_samples(bytes, channel)).samples;
}

// Load the chosen model now — downloading it if the browser doesn't have it —
// so the first real request doesn't wait. Done by recognising half a second of
// silence, which is the one thing the Worker knows how to be asked; the
// session stays warm afterwards like any other.
export async function preload_model({ onstage = null } = {}){
    on_stage = onstage;
    const s = await session();
    try {
        await s.transcribe(new Float32Array(8000), { timestamps: false });
    }
    finally {
        if(on_stage === onstage) on_stage = null;
        if(shared) release();
    }
}

// In-browser ASR over a stretch of one channel, not the whole recording: only
// the stretch's bytes are read, decoded and transcribed, and the segments come
// back timed from the start of the recording. A whole-file run asked for a
// stretch used to transcribe everything and keep what fitted inside it — all
// the time of a full run, and the segment that ran past the stretch's end
// lost. `span` is { beg, end }, end possibly Infinity.
export async function transcribe_stretch(docid, span, { ldc, docids, source_uid_channels, onprogress = null }){
    const { source_uid, channel } = source_for(docid, docids, source_uid_channels);
    const audio = await audio_of(source_uid, ldc);
    const beg = Math.max(0, span.beg ?? 0);
    const end = Math.min(span.end ?? Infinity, audio.info.duration);
    const bytes = await segment_bytes(audio, beg, end);
    const segments = await run_local_asr(bytes, { onprogress, channel: 'ch_0', decode: (b) => decode_to_samples(b, channel) });
    return offset_segments(segments, beg);
}

// One segment's recognised text, written nowhere — for ASR suggestions, which
// are shown before anything is saved. A segment's text is all that's used, so
// no timestamps: they are extra tokens for the model to produce.
export async function transcribe_one(row, { ldc, docids, source_uid_channels, onstage = null }){
    on_stage = onstage;
    const s = await session();
    try {
        return await s.transcribe(await samples_for(row, { ldc, docids, source_uid_channels }), { timestamps: false });
    }
    finally {
        if(on_stage === onstage) on_stage = null;
        if(shared) release();
    }
}

// `rows` are segment rows (transcript.segments). `write(row, text)` writes a
// segment's text if it is still empty. `onstage` hears the model's own
// progress — loading it, then 'transcribing' per request — and `onprogress`
// the segments done.
export async function run_segment_asr(rows, { ldc, docids, source_uid_channels, write, signal = null, onprogress = null, onstage = null }){
    on_stage = onstage;
    const s = await session();
    // Closing ends the request in flight, so a cancel doesn't wait for the
    // segment being recognised. The session goes with it.
    const on_abort = () => close_shared();
    signal?.addEventListener('abort', on_abort, { once: true });

    const transcriber = { transcribe: (samples) => s.transcribe(samples, { timestamps: false }) };
    const read = (row) => samples_for(row, { ldc, docids, source_uid_channels });

    try {
        return await transcribe_rows(rows, { samples_for: read, session: transcriber, write, signal, onprogress });
    }
    finally {
        signal?.removeEventListener('abort', on_abort);
        if(on_stage === onstage) on_stage = null;
        if(shared) release();
    }
}
