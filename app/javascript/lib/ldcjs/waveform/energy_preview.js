// Segments from sound level, as a span layer rather than as segments: the
// same measurement as Services 6 (energy_run.js), nothing written. Every
// span found is kept, including any over an existing segment — a preview is
// for looking at; gap-filling applies when one is added (span_promote.js).

import { run_energy_segments_for } from './energy_run';
import { add_layer } from './span_layers.svelte';
import { energy_label } from './energy_segments';

// A kit whose channels are separate files has a docid per file; one file with
// several channels has a docid per channel (asr.svelte.js does the same).
export async function preview_energy({ span, params, ldc, docids, source_uid_channels }){
    const separate = source_uid_channels.length > 1;
    const sources = separate ? source_uid_channels : [ source_uid_channels[0] ];
    const segments = [];
    const floors = [];
    const rejected = { not_enough_sound: 0, too_spread: 0 };
    for(let f = 0; f < sources.length; f++){
        const per_channel = await run_energy_segments_for(sources[f], ldc, {
            span, params, channels: separate ? 1 : Math.max(1, docids.length)
        });
        per_channel.forEach( (r, c) => {
            const docid = separate ? docids[f] : (docids[c] ?? docids[0]);
            floors.push(r.floor);
            rejected.not_enough_sound += r.rejected?.not_enough_sound ?? 0;
            rejected.too_spread += r.rejected?.too_spread ?? 0;
            for(const s of r.segments) segments.push({ beg: s.beg, end: s.end, docid });
        } );
    }
    const db = floors.filter( (x) => x != null ).map( (x) => `${Math.round(x)} dB` );
    return add_layer({
        label: energy_label(params, span),
        source: 'energy',
        params,
        note: [
            db.length ? `background ${db.join(', ')}` : null,
            rejected.not_enough_sound ? `${rejected.not_enough_sound} rejected as mostly background (clicks)` : null,
            rejected.too_spread ? `${rejected.too_spread} rejected as too uneven (knocks)` : null
        ].filter(Boolean).join('; ') || null,
        segments
    });
}
