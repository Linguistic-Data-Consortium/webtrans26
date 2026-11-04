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
//     on the main thread that is a frozen page. (The same library can run on
//     the main thread, but only for clips a few seconds long.)
//   - Decoding does NOT run in the Worker, and cannot: the Web Audio API is
//     exposed on Window only, so there is no AudioContext there to call
//     decodeAudioData on. It costs nothing to decode here — decodeAudioData is
//     asynchronous and the browser does the work off-thread.
//
// Accuracy is below the hosted service, deliberately. The trade is privacy:
// the audio never leaves the annotator's machine, which is the trust boundary
// this module exists to respect. The model and quantisation are chosen by the
// asr-model and asr-dtype meta tags, defaulting to whisper-base.en at q8 --
// about 77 MB on a first run, then cached by the browser.

import { round_to_6_places } from './waveform/times';
import { local_file_for } from './local_audio';
import { language_code } from './whisper_languages';

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

// Which model to run, from a size and a language.
//
// English runs the English-only model of the size, which is better at English
// than the multilingual one; any other language runs the multilingual model,
// told which language it is — the library can't detect one, and given none it
// transcribes as English. A size and a language can each be chosen for this
// browser (the Downloaded resources dialog); otherwise the server's asr-model
// gives the size and its asr-language the language. A server model that isn't
// one of these is used as named: a deployment's own choice.
export function asr_model(){
    return model_for({ server: server_model(), size: chosen_size(), language: asr_language() });
}
export function server_model(){ return meta('asr-model', DEFAULT_MODEL); }

const STANDARD = /^onnx-community\/whisper-(tiny|base|small)(\.en)?$/;

export function model_for({ server, size = null, language = 'en' }){
    const m = STANDARD.exec(server);
    if(!size && !m) return server;
    const s = size ?? m[1];
    return language === 'en' ? `onnx-community/whisper-${s}.en` : `onnx-community/whisper-${s}`;
}

// English-only models refuse to be told a language; the others need telling.
export function is_english_only(model){
    return /\.en$/.test(model);
}

// The language a run tells the model, or null for an English-only one.
export function run_language(model = asr_model()){
    return is_english_only(model) ? null : asr_language();
}

// "Whisper base (multilingual)" for onnx-community/whisper-base.
export function model_label(id){
    const m = STANDARD.exec(id);
    if(!m) return id;
    return `Whisper ${m[1]} (${m[2] ? 'English' : 'multilingual'})`;
}

// What the dialog offers. All have the quantised (q8) weights asr_dtype asks
// for; sizes are what the host reports once downloaded, not listed here.
export const ASR_SIZES = Object.freeze([
    { id: 'tiny',  label: 'Tiny',  note: 'smallest and fastest, least accurate' },
    { id: 'base',  label: 'Base',  note: 'the default balance' },
    { id: 'small', label: 'Small', note: 'about four times base: slowest, most accurate' }
]);

const SIZE_KEY = 'asr_size';
const LANGUAGE_KEY = 'asr_language';

export function chosen_size(){
    try {
        const v = localStorage.getItem(SIZE_KEY);
        return ASR_SIZES.some( (x) => x.id == v ) ? v : null;
    }
    catch(e){ return null; }
}

// null goes back to the server's.
export function choose_size(size){
    try {
        if(size) localStorage.setItem(SIZE_KEY, size);
        else     localStorage.removeItem(SIZE_KEY);
    }
    catch(e){}
}

export function server_language(){
    return language_code(meta('asr-language', 'en')) ?? 'en';
}

export function chosen_language(){
    try { return language_code(localStorage.getItem(LANGUAGE_KEY)); } catch(e){ return null; }
}

export function asr_language(){
    return chosen_language() ?? server_language();
}

// A code, or null to go back to the server's. Anything Whisper doesn't know
// is refused rather than kept.
export function choose_language(code){
    const c = code == null ? null : language_code(code);
    if(code != null && c == null) throw new Error(`Whisper doesn't know the language "${code}"`);
    try {
        if(c) localStorage.setItem(LANGUAGE_KEY, c);
        else  localStorage.removeItem(LANGUAGE_KEY);
    }
    catch(e){}
}

// One pass of the model per window, skipping Whisper's seek loop
// (asr_windows.js, pipeline_options): experimental, per browser, for
// whole-file runs.
const SINGLE_PASS_KEY = 'asr_single_pass';
export function single_pass_on(){
    try { return localStorage.getItem(SINGLE_PASS_KEY) === 'on'; } catch(e){ return false; }
}
export function set_single_pass(on){
    try {
        if(on) localStorage.setItem(SINGLE_PASS_KEY, 'on');
        else   localStorage.removeItem(SINGLE_PASS_KEY);
    }
    catch(e){}
}

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
//
// `channel` picks one channel of a stereo file. Never a mix of them: a mix
// makes one transcript of two speakers talking over each other.
export async function decode_to_samples(bytes, channel = 0){
    const Ctx = audio_context_class();
    if(!Ctx) throw new Error('no AudioContext: this browser cannot decode audio here');
    const ctx = new Ctx({ sampleRate: SAMPLE_RATE });
    try {
        const buffer = await ctx.decodeAudioData(bytes);
        // A whole-file run uses channel 0 and is run once per channel, the way
        // the service path iterates source_uid_channels.
        const c = Math.min(channel, buffer.numberOfChannels - 1);
        return { samples: buffer.getChannelData(c), duration: buffer.duration };
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
        language = run_language(model),
        base = asr_model_base(),
        dtype = asr_dtype(),
        single_pass = single_pass_on(),
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
                else if(m.type === 'done'){
                    // Which backend ran it, for whoever is timing the run.
                    onprogress?.({ stage: 'done', device: m.device, timing: m.timing });
                    resolve(chunks_to_segments(m.chunks, { duration, channel, speaker }));
                }
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
            worker.postMessage({ type: 'run', samples, model, base, dtype, webgpu: webgpu_available(), single_pass, language }, [ samples.buffer ]);
        });
    }
    finally {
        if(signal && on_abort) signal.removeEventListener('abort', on_abort);
        worker.terminate();
    }
}

// What a segment's recognised text is worth keeping as. Whisper describes what
// it hears when it hears no speech — "[BLANK_AUDIO]", "(upbeat music)",
// "[Music]" — and those are not words anyone said, so they go, and a segment
// that was nothing else comes back empty. Everything else is left as the model
// wrote it.
export function clean_segment_text(text){
    return String(text ?? '')
        .replace(/\[[^\]]*\]|\([^)]*\)/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

// One Worker kept for a run of short transcriptions — segment after segment —
// so the model is loaded once rather than once each, which would cost seconds
// a segment. The Worker already keeps its pipeline between messages
// (local_asr_worker.js); run_local_asr simply never asks it twice.
//
//   const session = await open_local_asr_session({ onprogress });
//   const text = await session.transcribe(samples);   // 16 kHz mono
//   session.close();
//
// Requests are queued, one at a time: the Worker answers 'done' without saying
// which request it is answering. A failed request rejects its own promise and
// leaves the session usable for the next.
export async function open_local_asr_session(opts = {}){
    const {
        onprogress = null,
        model = asr_model(),
        language = run_language(model),
        base = asr_model_base(),
        dtype = asr_dtype(),
        worker_factory = default_worker
    } = opts;
    const worker = await worker_factory();
    let queue = Promise.resolve();
    let closed = false;
    // The request in flight, so closing can end it: a terminated Worker never
    // answers, and a promise waiting on it would wait for ever.
    let in_flight = null;

    // `timestamps: false` asks for text alone, which is less for the model to
    // produce; the default keeps the timestamps a whole-file run needs.
    function run(samples, { timestamps = true } = {}){
        if(closed) return Promise.reject(new Error('cancelled'));
        return new Promise((resolve, reject) => {
            in_flight = reject;
            worker.onmessage = (e) => {
                const m = e.data || {};
                if(m.type === 'progress') onprogress?.(m);
                else if(m.type === 'done'){
                    const text = m.text ?? (m.chunks || []).map( (c) => c?.text ?? '' ).join(' ');
                    resolve(clean_segment_text(text));
                }
                else if(m.type === 'error') reject(new Error(m.message || 'local ASR failed'));
            };
            worker.onerror = (e) => reject(new Error(worker_failure_message(e)));
            worker.postMessage({ type: 'run', samples, model, base, dtype, webgpu: webgpu_available(), timestamps, language }, [ samples.buffer ]);
        });
    }

    return {
        transcribe(samples, opts){
            const p = queue.then( () => run(samples, opts) );
            queue = p.catch( () => {} );
            return p;
        },
        close(){
            closed = true;
            worker.terminate();
            in_flight?.(new Error('cancelled'));
        }
    };
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
    open_local_asr_session, clean_segment_text, decode_to_samples, run_language,
    local_asr_available, webgpu_available, asr_model, asr_model_base, asr_dtype
};
