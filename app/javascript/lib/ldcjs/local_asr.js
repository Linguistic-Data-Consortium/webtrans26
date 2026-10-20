// Speech recognition that runs in the annotator's own browser.
//
// The audio never leaves the machine. It is decoded here, the samples go to a
// Worker, and the Worker runs a Whisper model the browser fetched once and
// cached. What comes back is the `{ beg, end, text, speaker, channel }` shape
// every service in waveform/services.js is already normalised to, so nothing
// downstream has to know where a transcript came from.
//
// Why the work is split the way it is:
//
//   - Inference runs in a Worker because a run takes seconds to minutes, and
//     on the main thread that is a frozen page. (`ugain` runs the same library
//     on the main thread, which is survivable only because its clips are a few
//     seconds long.)
//   - Decoding does NOT run in the Worker, and cannot: the Web Audio API is
//     exposed on Window only, so there is no AudioContext there to call
//     decodeAudioData on. It costs nothing to decode here — decodeAudioData is
//     asynchronous and the browser does the work off-thread.
//
// Accuracy is below the hosted service, deliberately: see
// app_comparison/ports/local-stt.md, which is also where the model choice and
// the trust-boundary decision behind this module are recorded.

import { round_to_6_places } from './waveform/times';
import { local_file_for } from './local_audio';

// Whisper wants 16 kHz mono, and asking the AudioContext for that rate lets
// the browser resample during decode rather than us doing it badly afterwards.
const SAMPLE_RATE = 16000;

// A model small enough to be a tolerable first download and good enough to be
// worth correcting. Overridable per deployment, which is the point of the meta
// tag below. Phase 5 of the spec replaces this default with a measured one.
const DEFAULT_MODEL = 'onnx-community/whisper-base.en';

// Read lazily, for the same reason service_config.js does: this module is
// imported by tests and by code that can run before the document is parsed,
// and a value captured at import time would be the fallback for the session.
function meta(name, fallback){
    if(typeof document === 'undefined') return fallback;
    const el = document.querySelector(`meta[name="${name}"]`);
    const v = el && el.content;
    return (v && v.length) ? v : fallback;
}

// Which model to run. A deployment that wants `whisper-small.en`, or a
// multilingual model, says so here rather than in the code.
export function asr_model(){ return meta('asr-model', DEFAULT_MODEL); }

// How heavily the weights are quantised, which decides the download. For
// whisper-base.en, measured from the model repo:
//
//     fp32   291 MB      the library's own default on any device but wasm
//     fp16   146 MB
//     q4     142 MB
//     q8      77 MB      <- default here
//
// q8 because this is a per-annotator download over whatever connection they
// have, and 291 MB is not a thing to ask for by accident — which is exactly
// what passing 'fp32' for WebGPU was doing. Whether fp16 or q4 earns its extra
// ~70 MB in speed or accuracy on WebGPU is phase 5's measurement, and a
// deployment that has measured it says so here.
export function asr_dtype(){ return meta('asr-dtype', 'q8'); }

// Where the weights come from. Empty means the library's own default host.
// An instance that must work offline, or that may not talk to a third party at
// all, serves the files from its own origin and names it here. Weights are not
// audio — fetching them breaks neither the trust boundary nor this module —
// but they do require the network, which an air-gapped deployment lacks.
export function asr_model_base(){ return meta('asr-model-base', ''); }

// Whether a run is possible at all. Both halves are needed and neither exists
// in jsdom, which is why the tests inject their own.
export function local_asr_available(){
    return typeof Worker !== 'undefined' && typeof audio_context_class() === 'function';
}

// WebGPU makes the difference between a run an annotator will wait for and one
// they will not. Its absence is not fatal — the WASM backend is the fallback,
// single-threaded because the app sends no COOP/COEP headers.
export function webgpu_available(){
    return typeof navigator !== 'undefined' && Boolean(navigator.gpu);
}

function audio_context_class(){
    if(typeof window === 'undefined') return undefined;
    return window.AudioContext || window.webkitAudioContext;
}

// The library's chunks into this app's segments.
//
// Exported because it is the part worth testing: everything else here is a
// Worker and a decoder, and this is where a wrong answer would quietly produce
// segments at the wrong times.
//
// Two things the library's own types do not prepare you for, both real:
// `timestamp` is declared `[number, number]` but is `Array<number|null>` in
// the Whisper decoder, and the last chunk of a run routinely has a null end.
// A null end becomes the end of the audio; a null start is unusable and the
// chunk is dropped.
export function chunks_to_segments(chunks, opts = {}){
    const { duration = null, channel = 'ch_0', speaker = '0' } = opts;
    const out = [];
    for(const chunk of (chunks || [])){
        const text = (chunk?.text ?? '').trim();
        if(!text) continue;

        const [ raw_beg, raw_end ] = chunk.timestamp || [];
        if(typeof raw_beg !== 'number' || !isFinite(raw_beg)) continue;

        let end = (typeof raw_end === 'number' && isFinite(raw_end)) ? raw_end : duration;
        if(typeof end !== 'number' || !isFinite(end)) continue;
        if(duration !== null && end > duration) end = duration;

        const beg = round_to_6_places(Math.max(0, raw_beg));
        end = round_to_6_places(end);
        // A zero-length segment has no audio to point at. The service path
        // drops these too (split_word_sequence filters beg == end).
        if(end <= beg) continue;

        out.push({ beg, end, text, speaker, channel });
    }
    return out;
}

// Audio in, 16 kHz mono samples out. `bytes` is an ArrayBuffer.
async function decode_to_samples(bytes){
    const Ctx = audio_context_class();
    if(!Ctx) throw new Error('no AudioContext: this browser cannot decode audio here');
    const ctx = new Ctx({ sampleRate: SAMPLE_RATE });
    try {
        const buffer = await ctx.decodeAudioData(bytes);
        // Channel 0 only. A stereo kit is transcribed one channel per run, the
        // way the service path iterates source_uid_channels — mixing the two
        // would make one transcript of two speakers talking over each other.
        return { samples: buffer.getChannelData(0), duration: buffer.duration };
    }
    finally {
        if(typeof ctx.close === 'function') await ctx.close();
    }
}

// A Blob, a File, or a url into an ArrayBuffer.
async function bytes_for(audio){
    if(audio instanceof ArrayBuffer) return audio;
    if(typeof Blob !== 'undefined' && audio instanceof Blob) return audio.arrayBuffer();
    if(typeof audio === 'string'){
        // A local_audio kit's url is a blob: url standing in for a File the
        // page already holds. Read the File; do not fetch the url.
        //
        // Two reasons, and the first is fatal: fetch() is governed by
        // connect-src, which lists 'self', wss:, https: and *.amazonaws.com —
        // not blob: — so fetching a blob: url fails as
        // "TypeError: Failed to fetch", with the CSP violation visible only in
        // the console. The second is that the bytes are already in memory, so
        // the round trip buys nothing. getp_wav reads local files the same way
        // for the same reasons (getp.js:106).
        const file = local_file_for(audio);
        if(file) return file.arrayBuffer();
        // Anything else is a real request, and the two ways it fails are worth
        // telling apart: a 4xx/5xx from the host, or a TypeError, which for a
        // cross-origin audio url usually means CORS rather than a dead host.
        let r;
        try { r = await fetch(audio); }
        catch(e){ throw new Error(`could not fetch the audio at ${audio} (${e?.message || e}) — if it is on another host, check its CORS headers`); }
        if(!r.ok) throw new Error(`could not read the audio at ${audio}: HTTP ${r.status}`);
        return r.arrayBuffer();
    }
    throw new Error('unusable audio: expected a Blob, an ArrayBuffer or a url');
}

// The worker, through vite's `?worker` import rather than by url.
//
// This was `new Worker(new URL('./local_asr_worker.js', import.meta.url))`,
// which works — but only while that exact expression sits at the construction
// site. Vite's worker plugin matches the shape syntactically; lifting the url
// into a variable or a helper leaves it untransformed, and the request then
// goes to the *source* path (…/vite-dev/lib/ldcjs/local_asr_worker.js), which
// the build never emits. That is a silent trap: the code reads fine and fails
// only at run time, in the built app.
//
// `?worker` has no such shape requirement. Vite emits the chunk, owns the url,
// and handles the dev case where assets come from another origin — which a
// hand-written Worker cannot, since the browser refuses a cross-origin worker
// script outright (SecurityError).
//
// Imported dynamically so the module stays importable where `?worker` has no
// meaning: the tests inject their own factory and never call this.
async function default_worker(){
    const { default: LocalAsrWorker } = await import('./local_asr_worker.js?worker');
    return new LocalAsrWorker();
}

// Why a worker died, when the browser won't say.
//
// A worker that fails to load fires an ErrorEvent with an empty message —
// measured in a browser, not assumed — so without this, "the worker failed to
// start" is all the calling code can see.
function worker_failure_message(event){
    const said = event?.message || '';
    if(said) return said;
    return 'the speech recognition worker loaded but failed to start, and the browser gave no reason — the console will have it, usually a Content-Security-Policy refusal (worker-src) or an error thrown while the module initialised';
}

// Transcribe `audio` here, in this browser.
//
//   audio    a Blob/File, an ArrayBuffer, or a url to fetch
//   opts     channel, speaker  — stamped onto every segment
//            onprogress({ stage, loaded, total, file })
//            signal            — an AbortSignal; aborting terminates the Worker
//            model, base       — override the meta tags
//            decode, worker_factory — seams for the tests
//
// Resolves with the segment array described above. Rejects with an Error whose
// message is meant to be shown: a caller that cannot run has to say why.
export async function run_local_asr(audio, opts = {}){
    const {
        channel = 'ch_0',
        speaker = '0',
        onprogress = null,
        signal = null,
        model = asr_model(),
        base = asr_model_base(),
        dtype = asr_dtype(),
        decode = decode_to_samples,
        worker_factory = default_worker
    } = opts;

    const bytes = await bytes_for(audio);
    if(signal?.aborted) throw new Error('cancelled');

    onprogress?.({ stage: 'decoding' });
    const { samples, duration } = await decode(bytes);
    if(signal?.aborted) throw new Error('cancelled');

    const worker = await worker_factory();
    let on_abort = null;

    try {
        return await new Promise((resolve, reject) => {
            worker.onmessage = (e) => {
                const m = e.data || {};
                if(m.type === 'progress') onprogress?.(m);
                else if(m.type === 'done') resolve(chunks_to_segments(m.chunks, { duration, channel, speaker }));
                else if(m.type === 'error') reject(new Error(m.message || 'local ASR failed'));
            };
            // A Worker that dies — a missing model, an import that fails —
            // otherwise leaves this promise pending for ever, and the progress
            // panel hides the transcript while a run is in flight.
            worker.onerror = (e) => reject(new Error(worker_failure_message(e)));

            if(signal){
                on_abort = () => reject(new Error('cancelled'));
                signal.addEventListener('abort', on_abort, { once: true });
            }

            // The samples are transferred, not copied: a long recording is
            // tens of megabytes and this is the one place that matters.
            worker.postMessage({ type: 'run', samples, model, base, dtype, webgpu: webgpu_available() }, [ samples.buffer ]);
        });
    }
    finally {
        if(signal && on_abort) signal.removeEventListener('abort', on_abort);
        worker.terminate();
    }
}

// The audio the waveform is already drawing, as something fetchable.
//
// `ldc.resources.urls` is keyed by docid and holds whatever this kit's audio
// turned out to be: the blob: url a local_audio file is registered under, a
// plain http(s) url, or — for an s3:// source — the presigned https url that
// signed_url_for_audio wrote back over the s3 path (waveform/helpers.js:81).
// So by the time a kit is open this is a url `fetch` can read, whatever the
// kit type, and the local engine needs no S3 knowledge of its own.
export function audio_url_for(docid, ldc){
    const url = ldc?.resources?.urls?.[docid];
    if(!url) throw new Error(`no audio url for ${docid}`);
    // An s3: path that was never signed would fetch as a relative url and
    // 404 somewhere unhelpful. Say which of the two things went wrong.
    if(/^s3(:|\/)/.test(url)) throw new Error(`the audio for ${docid} has not been signed yet`);
    return url;
}

// One channel of one kit, transcribed here. This is what the ASR run calls,
// once per docid, so the stereo loop in asr.svelte.js works unchanged: each
// channel has its own docid and its own url.
//
// `async` for a reason worth keeping: audio_url_for throws, and a synchronous
// throw here would escape xasr() rather than reaching run_asr4_helper's
// .catch — leaving asro.status at 'pending' and bulk_end() uncalled, which
// hides the transcript behind the progress panel until a reload. As a
// rejection it lands where every other service failure lands.
export async function run_local_asr_for(docid, ldc, opts = {}){
    return run_local_asr(audio_url_for(docid, ldc), opts);
}

export default {
    run_local_asr, run_local_asr_for, audio_url_for, chunks_to_segments,
    local_asr_available, webgpu_available, asr_model, asr_model_base, asr_dtype
};
