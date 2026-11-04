// Spans into real segments — the one point where a span layer reaches the
// annotation log. Gap-filling, as every segment-making run here is: a span
// touching an existing segment on the same channel is skipped. Added through
// add_audio_to_list, the path ASR results take, in batches behind the progress
// panel.

import { add_audio_to_list, add_audio_to_listq } from './modification1';
import { BATCH_SIZE, bulk_start, bulk_done, bulk_end, bulk_after_paint } from './bulk.svelte';
import { drop_overlapping } from './spans';
import { transcript } from './transcript.svelte';
import { round_to_3_places } from './times';

// `spans` are [ { beg, end, docid, text? } ]. Resolves with { added, skipped }
// once the server has the last batch.
export function add_spans_as_segments(spans){
    const { kept, skipped } = drop_overlapping(spans, transcript.segments, (s) => s.docid);
    if(kept.length == 0) return Promise.resolve({ added: 0, skipped });
    return new Promise( (resolve) => {
        bulk_start('Adding segments', kept.length);
        const batch = (i) => {
            bulk_done(i);
            if(i >= kept.length){
                bulk_end();
                resolve({ added: kept.length, skipped });
                return;
            }
            let j = i;
            while(j < i + BATCH_SIZE && j < kept.length){
                const s = kept[j++];
                add_audio_to_list(s.docid, null, null, {
                    offset: s.beg,
                    length: round_to_3_places(s.end - s.beg),
                    transcript: s.text || undefined
                });
            }
            add_audio_to_listq( () => batch(j) );
        };
        bulk_after_paint( () => batch(0) );
    } );
}
