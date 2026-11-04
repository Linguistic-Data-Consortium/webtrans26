// What this app keeps in the annotator's browser, for the Downloaded
// resources dialog to show and clear.
//
//   downloads         speech models, the recognition runtime, any optional
//                     WASM module — whatever is registered in resources/,
//                     each in a Cache Storage cache read and cleared here.
//                     Cache Storage is per origin, so a Worker's downloads
//                     are visible to the page.
//   local audio       file handles kept per kit (local_audio_handles.js)
//   settings          the few per-browser choices in localStorage (SETTINGS)
//
// The browser may evict all of it under storage pressure unless asked not to
// (keep_from_eviction).

function cache_api(){
    return typeof caches === 'undefined' ? null : caches;
}

// Every entry in a cache with its size: the stored Content-Length where there
// is one, which saves reading tens of megabytes to count them. A cache that
// doesn't exist reads as empty (and isn't created by asking).
export async function read_cache(name, store = cache_api()){
    if(!store || !(await store.has(name))) return [];
    const cache = await store.open(name);
    const out = [];
    for(const req of await cache.keys()){
        const res = await cache.match(req);
        let size = Number(res?.headers.get('content-length'));
        if(!size && res) size = (await res.blob()).size;
        out.push({ url: req.url, size: size || 0 });
    }
    return out;
}

export async function delete_cache_files(name, urls, store = cache_api()){
    if(!store || !(await store.has(name))) return;
    const cache = await store.open(name);
    for(const u of urls) await cache.delete(u);
}

// How much this site uses of what the browser allows it, and whether the
// browser has promised to keep it.
export async function storage_overview(){
    const s = typeof navigator !== 'undefined' ? navigator.storage : null;
    const est = s?.estimate ? await s.estimate().catch( () => ({}) ) : {};
    const persisted = s?.persisted ? await s.persisted().catch( () => false ) : false;
    return { usage: est.usage ?? null, quota: est.quota ?? null, persisted, can_persist: !!s?.persist };
}

// Ask the browser not to evict this site's storage. It decides: Chrome grants
// it from engagement (a site used often, or installed), Firefox may ask the
// user. Resolves true if granted.
export async function keep_from_eviction(){
    const s = typeof navigator !== 'undefined' ? navigator.storage : null;
    if(!s?.persist) return false;
    return s.persist().catch( () => false );
}

// The per-browser choices this app keeps, and what each one is.
export const SETTINGS = Object.freeze([
    { key: 'asr_size',        label: 'Speech model size' },
    { key: 'asr_language',    label: 'Language the speech model listens for' },
    { key: 'asr_preview',     label: 'ASR suggestions on or off' },
    { key: 'asr_single_pass', label: 'One pass per window (experimental)' },
    { key: 'energy_segments', label: 'Settings for segments from sound level' }
]);

export function read_settings(){
    return SETTINGS.map( (s) => {
        let value = null;
        try { value = localStorage.getItem(s.key); } catch(e){}
        return { ...s, value };
    } );
}

export function reset_setting(key){
    try { localStorage.removeItem(key); } catch(e){}
}

export function format_bytes(n){
    if(n == null) return '–';
    if(n < 1024) return `${n} B`;
    const units = [ 'KB', 'MB', 'GB', 'TB' ];
    let v = n, u = -1;
    do { v /= 1024; u++; } while(v >= 1024 && u < units.length - 1);
    return `${v >= 10 ? Math.round(v) : v.toFixed(1)} ${units[u]}`;
}
