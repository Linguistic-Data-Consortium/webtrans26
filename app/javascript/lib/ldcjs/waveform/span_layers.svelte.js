// Span layers: spans kept in this browser, shown, never saved as annotations.
//
// A store any feature can write to — it knows nothing about what made the
// spans. Sound-level segmentation's Preview is the first (energy_preview.js);
// anything else that produces spans adds a layer the same way:
//
//   import { add_layer } from './span_layers.svelte';
//   await add_layer({ label: 'What made these', source: 'my-feature',
//                     params: { …the settings }, note: 'one line, optional',
//                     segments: [ { beg, end, docid, text? }, … ] });
//
// Each layer has a name, a colour and its spans. Layers are drawn in a lane
// under the waveform (PreviewLane.svelte), can be hidden or removed, and become
// real segments only when asked (span_promote.js) — a whole layer or a single
// span, filling gaps only.
//
// Kept per kit in IndexedDB ('span_layers'), so they survive a reload; never
// sent to the server. The Downloaded resources dialog lists and clears them.

import { kv_store } from '../kv_store';
import { next_color } from './span_geometry';
import { span_problem } from './spans';

const default_store = () => kv_store('span_layers', 'layers');

export const span_layers = $state({
    kit: null,
    layers: [],
    // The span picked in the lane: { layer, i } or null.
    selected: null
});

let store = null;
const db = () => (store ??= default_store());

// For tests: another store (a Map-backed stand-in).
export function use_store(s){ store = s; }

async function save(){
    if(!span_layers.kit) return;
    // A rune is a proxy, which IndexedDB can't clone.
    await db().put(span_layers.kit, $state.snapshot(span_layers.layers));
}

export async function load_previews(kit){
    span_layers.kit = kit;
    span_layers.selected = null;
    try {
        span_layers.layers = (await db().get(kit)) ?? [];
    }
    catch(e){
        span_layers.layers = [];
    }
}

let counter = 0;

// A new layer, shown, in the next free colour. `segments` are
// [ { beg, end, docid, text? } ]; kept in time order. A feature handing over a
// bad span is told which and why, rather than the store keeping something the
// lane can't place or a promotion can't add.
export async function add_layer({ label, source = null, params = null, note = null, segments }){
    if(typeof label !== 'string' || label === '') throw new Error('a span layer needs a label');
    if(!Array.isArray(segments)) throw new Error('a span layer needs segments: an array of spans');
    segments.forEach( (s, i) => {
        const p = span_problem(s);
        if(p) throw new Error(`span ${i} of "${label}": ${p}`);
    } );
    const layer = {
        id: `${Date.now().toString(36)}-${(counter++).toString(36)}`,
        label,
        source,
        params,
        note,
        color: next_color(span_layers.layers),
        visible: true,
        created: new Date().toISOString(),
        segments: [ ...segments ].sort( (a, b) => a.beg - b.beg || a.end - b.end )
    };
    span_layers.layers.push(layer);
    await save();
    return layer;
}

export async function update_layer(id, changes){
    const l = span_layers.layers.find( (x) => x.id === id );
    if(!l) return;
    Object.assign(l, changes);
    await save();
}

export async function remove_layer(id){
    span_layers.layers = span_layers.layers.filter( (x) => x.id !== id );
    if(span_layers.selected?.layer === id) span_layers.selected = null;
    await save();
}

export function select_span(layer, i){
    span_layers.selected = { layer, i };
}

export function selected_span(){
    const s = span_layers.selected;
    if(!s) return null;
    const l = span_layers.layers.find( (x) => x.id === s.layer );
    const span = l?.segments[s.i];
    return span ? { layer: l, span } : null;
}

// Every kit with previews kept in this browser, for the resources dialog:
// [ { kit, layers, spans } ].
export async function list_all_previews(){
    const kits = await db().keys();
    const out = [];
    for(const kit of kits){
        const layers = (await db().get(kit)) ?? [];
        out.push({ kit, layers: layers.length, spans: layers.reduce( (n, l) => n + l.segments.length, 0 ) });
    }
    return out;
}

export async function clear_previews(kit){
    await db().delete(kit);
    if(kit === span_layers.kit){
        span_layers.layers = [];
        span_layers.selected = null;
    }
}
