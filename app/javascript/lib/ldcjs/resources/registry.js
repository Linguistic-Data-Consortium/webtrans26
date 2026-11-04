// Optional things the app downloads on demand and keeps in the browser — a
// speech model, a WASM module — registered here so the Downloaded resources
// dialog can list, size, download and delete them without knowing what any of
// them is.
//
// A resource lives in Cache Storage, under a cache it names. That is the one
// requirement: the browser's ordinary HTTP cache can't be listed or cleared by
// a page, so anything loaded through it is invisible here. define_wasm_module
// below loads through Cache Storage, which is why new modules should use it.
//
// A registration:
//
//   id            unique; also what keys default to
//   label(key)    what a row is called; or a string
//   description   one line about what it's for
//   cache         the Cache Storage name its files live in
//   key(url)      which row a cached url belongs to — a key — or null if it
//                 isn't this resource's. One resource can have several rows
//                 (a model family: a row per model).
//   keys()        rows to show even when nothing is downloaded yet, so they
//                 can be downloaded ahead. Default: none.
//   in_use(key)   true for the one the app is currently set to use
//   download(key, { onprogress })   fetch ahead; onprogress(pct | null).
//                 Omitted: the resource only arrives when it's first used.
//   can_download(key)   default: true when download exists
//   on_delete(key)      after its files are deleted — e.g. let go of a copy
//                       held in memory
//
// Registrations are made by modules imported from ./index.js, so the dialog
// knows about a resource before anything has loaded it.

const registry = new Map();

export function register_resource(def){
    if(!def?.id || !def.cache || typeof def.key !== 'function') throw new Error('a resource needs id, cache and key(url)');
    registry.set(def.id, def);
    return def;
}

export function registered(){
    return [ ...registry.values() ];
}

// for tests
export function unregister_all(){
    registry.clear();
}

export function caches_used(defs = registered()){
    return [ ...new Set(defs.map( (d) => d.cache )) ];
}

const label_of = (def, key) => typeof def.label === 'function' ? def.label(key) : (def.label ?? key);

// Cache entries as rows. `entries` is { cache name: [ { url, size } ] }.
// Each row: { id: `${def.id}:${key}`, def, key, label, description, files,
// size, downloaded, in_use, can_download }. Files in a registered cache that
// no resource claims become one "Other files" row per cache, so leftovers —
// an old runtime version, a model from before a change — can still be cleared.
export function rows_for(defs, entries){
    const rows = new Map();
    const claimed = new Set();
    const row = (def, key) => {
        const id = `${def.id}:${key}`;
        if(!rows.has(id)){
            rows.set(id, {
                id, def, key,
                label: label_of(def, key),
                description: def.description ?? '',
                files: [], size: 0, downloaded: false,
                in_use: !!def.in_use?.(key),
                can_download: !!def.download && (def.can_download ? !!def.can_download(key) : true)
            });
        }
        return rows.get(id);
    };
    for(const def of defs){
        for(const key of (def.keys?.() ?? [])) row(def, key);
        for(const e of entries[def.cache] ?? []){
            const key = def.key(e.url);
            if(key == null) continue;
            const r = row(def, key);
            r.files.push(e);
            r.size += e.size || 0;
            r.downloaded = true;
            claimed.add(`${def.cache}\n${e.url}`);
        }
    }
    const out = [ ...rows.values() ];
    for(const cache of caches_used(defs)){
        const left = (entries[cache] ?? []).filter( (e) => !claimed.has(`${cache}\n${e.url}`) );
        if(left.length == 0) continue;
        out.push({
            id: `other:${cache}`, def: null, key: cache,
            label: 'Other files', description: `in ${cache}, not claimed by anything this version of the app uses`,
            files: left, size: left.reduce( (n, e) => n + (e.size || 0), 0 ),
            downloaded: true, in_use: false, can_download: false
        });
    }
    return out;
}

// ── loading through Cache Storage ────────────────────────────────────────

function cache_api(){
    return typeof caches === 'undefined' ? null : caches;
}

// `url`'s response, from `cache` if it's there, else fetched and put there.
// onprogress(loaded, total) while fetching; total is null when the server
// doesn't say. Without Cache Storage (an insecure origin, say) it just
// fetches, and nothing is kept.
export async function cached_fetch(cache_name, url, { onprogress = null, store = cache_api(), fetch_impl = fetch } = {}){
    const cache = store ? await store.open(cache_name) : null;
    const hit = await cache?.match(url);
    if(hit) return hit;
    const res = await fetch_impl(url);
    if(!res.ok) throw new Error(`could not fetch ${url}: HTTP ${res.status}`);
    const total = Number(res.headers.get('content-length')) || null;
    let body;
    if(onprogress && res.body?.getReader){
        const reader = res.body.getReader();
        const parts = [];
        let loaded = 0;
        onprogress(0, total);
        for(;;){
            const { done, value } = await reader.read();
            if(done) break;
            parts.push(value);
            loaded += value.byteLength;
            onprogress(loaded, total);
        }
        body = new Uint8Array(loaded);
        let o = 0;
        for(const p of parts){ body.set(p, o); o += p.byteLength; }
    }
    else body = new Uint8Array(await res.arrayBuffer());
    // Stored with its length, so listing can size it without reading it.
    const headers = new Headers(res.headers);
    headers.set('content-length', String(body.byteLength));
    const kept = new Response(body, { status: 200, headers });
    await cache?.put(url, kept.clone());
    return kept;
}

// ── WASM modules ─────────────────────────────────────────────────────────

export const MODULE_CACHE = 'optional-modules';

// Register an optional WASM module and get back what loads it.
//
//   const vad = define_wasm_module({
//       id: 'vad', label: 'Voice activity detector',
//       description: 'Finds speech for Segments from sound level',
//       files: { wasm: '/modules/vad-1.2.0.wasm', glue: '/modules/vad-1.2.0.mjs' }
//   });
//   const bytes = await vad.bytes('wasm');                 // ArrayBuffer
//   const { instance } = await WebAssembly.instantiate(bytes, imports);
//
// Put a version in each url: a new version is a new url, so it downloads
// fresh, and the old one shows up as "Other files" until it's deleted.
export function define_wasm_module({ id, label, description = '', files, cache = MODULE_CACHE, used_by = null }){
    const urls = Object.values(files);
    const abs = (u) => new URL(u, typeof location === 'undefined' ? 'http://localhost/' : location.href).href;
    const mine = new Set(urls.map(abs));
    const download = async (_key, { onprogress } = {}) => {
        const sizes = new Map();
        for(const u of urls){
            await cached_fetch(cache, abs(u), {
                onprogress: (loaded, total) => {
                    sizes.set(u, { loaded, total });
                    const known = [ ...sizes.values() ];
                    const t = known.reduce( (n, s) => n + (s.total || 0), 0 );
                    onprogress?.(t ? Math.round(100 * known.reduce( (n, s) => n + s.loaded, 0 ) / t) : null);
                }
            });
        }
        onprogress?.(100);
    };
    register_resource({
        id, cache,
        label: label ?? id,
        description: used_by ? `${description} — used by ${used_by}` : description,
        key: (url) => mine.has(url) ? id : null,
        keys: () => [ id ],
        download
    });
    return {
        id,
        download: (opts) => download(id, opts),
        // A file's bytes, downloading the module first if it isn't kept yet.
        async bytes(name){
            if(!(name in files)) throw new Error(`${id} has no file called ${name}`);
            return (await cached_fetch(cache, abs(files[name]))).arrayBuffer();
        }
    };
}
