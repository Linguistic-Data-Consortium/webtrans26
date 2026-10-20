// The Worker that runs the speech model. The only file that imports the
// library, so nothing else in the bundle pulls in onnxruntime.
//
// It receives 16 kHz mono samples — decoded on the main thread, because the
// Web Audio API does not exist here — and posts back the library's chunks.
// Mapping those to segments is local_asr.js's job, where it can be tested.
//
// Protocol, in both directions:
//
//   in   { type: 'run', samples, model, base, webgpu }
//   out  { type: 'progress', stage, file?, loaded?, total? }
//        { type: 'done', chunks }
//        { type: 'error', message }
//
// See app_comparison/ports/local-stt.md.

import { pipeline, env } from '@huggingface/transformers';

// One pipeline per Worker, kept across runs in case the Worker is reused: the
// model is the expensive part, and loading it twice would download nothing
// (the browser caches the files) but would rebuild the session.
let transcriber = null;
let loaded_model = null;

async function get_transcriber(model, base, webgpu, post){
    if(transcriber && loaded_model === model) return transcriber;

    // An instance serving the weights from its own origin says so; otherwise
    // the library's default host is used. Local model files are off either
    // way: there is no filesystem here, and leaving it on makes the library
    // try a path that cannot exist before it tries the network.
    if(base) env.remoteHost = base;
    env.allowLocalModels = false;

    // WebGPU where the browser has it, WASM otherwise. The dtypes here are a
    // starting point, not a tuned choice — phase 5 of the spec measures this.
    const device = webgpu ? 'webgpu' : 'wasm';
    const dtype  = webgpu ? 'fp32' : 'q8';

    transcriber = await pipeline('automatic-speech-recognition', model, {
        device,
        dtype,
        progress_callback: (p) => post({
            type: 'progress',
            stage: p.status === 'progress' ? 'downloading' : (p.status || 'loading'),
            file: p.file,
            loaded: p.loaded,
            total: p.total
        })
    });
    loaded_model = model;
    return transcriber;
}

self.onmessage = async (e) => {
    const post = (m) => self.postMessage(m);
    const { type, samples, model, base, webgpu } = e.data || {};
    if(type !== 'run') return;

    try {
        const run = await get_transcriber(model, base, webgpu, post);
        post({ type: 'progress', stage: 'transcribing' });

        // chunk_length_s is what lets a recording longer than Whisper's 30s
        // window be transcribed at all; the stride is the overlap that stops
        // words being lost at the seams. return_timestamps is what makes the
        // result into segments rather than one undifferentiated string.
        const out = await run(samples, {
            chunk_length_s: 30,
            stride_length_s: 5,
            return_timestamps: true
        });

        post({ type: 'done', chunks: out?.chunks ?? [], text: out?.text ?? '' });
    }
    catch (err) {
        // The message is shown to the annotator, so pass something sayable
        // rather than the whole error.
        post({ type: 'error', message: err?.message || String(err) });
    }
};
