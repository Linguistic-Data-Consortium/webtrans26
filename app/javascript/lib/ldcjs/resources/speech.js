// The in-browser speech recognizer's downloads, as resources: one row per
// model, and the ONNX runtime the model runs on. Both live in the Cache
// Storage transformers.js downloads into, and both arrive on first use; the
// model can also be fetched ahead.

import { register_resource } from './registry';
import { asr_model, local_asr_available, model_label as label_for } from '../local_asr';
import { download_tracker } from '../waveform/segment_asr';

// The session runner reads audio through the AWS-aware helpers; imported when
// needed, so registering costs nothing and this module stays testable.
const runner = () => import('../waveform/segment_asr_run');
const close_session = () => runner().then( (m) => m.close_asr_session() );

export const MODEL_CACHE = 'transformers-cache';

// A model file's url names the model: …/<org>/<model>/resolve/<rev>/<path>,
// on the default host or a deployment's own (asr-model-base).
const MODEL_URL = /\/([^/]+\/[^/]+)\/resolve\/[^/]+\/.+$/;
// The runtime's own files: ort-wasm-simd-threaded[.variant].{wasm,mjs}.
const RUNTIME_URL = /\/ort-wasm[^/]*\.(wasm|mjs)(\?|$)/;

export function model_key(url){
    const m = MODEL_URL.exec(new URL(url, 'http://x').pathname);
    return m ? decodeURIComponent(m[1]) : null;
}

export function runtime_key(url){
    return RUNTIME_URL.test(url) ? 'runtime' : null;
}

export function model_label(id){
    return label_for(id);
}

register_resource({
    id: 'speech-model',
    cache: MODEL_CACHE,
    label: model_label,
    description: 'Speech recognition in this browser (Services 5 and 7, ASR suggestions)',
    key: model_key,
    // The model in use, downloaded or not, so it can be fetched ahead.
    keys: () => local_asr_available() ? [ asr_model() ] : [],
    in_use: (key) => key == asr_model(),
    // Loading is the only way to download one, and only the chosen model can
    // be loaded; another is chosen first, above the list.
    can_download: (key) => key == asr_model() && local_asr_available(),
    download: async (_key, { onprogress } = {}) => {
        const pct = download_tracker();
        const { preload_model } = await runner();
        await preload_model({ onstage: (m) => { const p = pct(m); if(p != null) onprogress?.(p); } });
    },
    // A session still holding it would carry on with it.
    on_delete: close_session
});

register_resource({
    id: 'speech-runtime',
    cache: MODEL_CACHE,
    label: 'Recognition runtime',
    description: 'The engine the speech model runs on; downloaded with the model',
    key: runtime_key,
    on_delete: close_session
});
