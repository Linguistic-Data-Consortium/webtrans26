import { add_sad_send } from './helpers';
import { split_word_sequence, add_asr_sendx, xasr_process } from './services';
import { services_configured } from '../service_config';
import { activeo } from './shared.svelte';
import { BATCH_SIZE, bulk_start, bulk_total, bulk_done, bulk_end } from './bulk.svelte';
import { round_to_6_places } from './times';
import {
    add_audio_to_list,
    add_audio_to_listq
} from './modification1';
const sado = $state({
    previous: false,
    status: null,
    i: null,
    source_uid: null,
    pending_promise: null,
    // promise: null,
    // result: null,
    segments: [],
    // items: null,
    // vvsegs: [],
    // addedn: 0,
    source_uid_channels: [],
    docids: [],
    sad_previous: []
});
const asro = $state({
    previous: false,
    type: null,
    status: null,
    i: null,
    source_uid: null,
    pending_promise: null,
    promise: null,
    result: null,
    segments: [],
    items: null,
    vvsegs: [],
    addedn: 0,
    source_uid_channels: [],
    docids: [],
    asr_previous: [],
    // The stretch of audio this run may fill, asked for before it starts
    // (AsrSpanDialog). null means the whole recording — which is what every
    // service returns, and what this used to add unconditionally.
    span: null
});

// Spans that fit inside the requested one, the others dropped.
//
// Containment rather than overlap: a segment half outside the span would be
// added at its own times, past the edge of what was asked for, and the point
// of asking is to bound what appears. A run with no span keeps everything.
//
// Applied once, here, rather than per service: every service's result reaches
// this as the same { beg, end, … } shape, so one filter covers azure, rev and
// the asr* family alike.
function filter_to_span(segments){
    const span = asro.span;
    if(!span || !Array.isArray(segments)) return segments;
    const kept = segments.filter( (s) => {
        const beg = Number(s.beg);
        const end = Number(s.end);
        if(Number.isNaN(beg) || Number.isNaN(end)) return false;
        return beg >= span.beg && end <= span.end;
    } );
    const end_label = span.end === Infinity ? 'end' : span.end;
    console.log(`[asr] span ${span.beg}–${end_label}: keeping ${kept.length} of ${segments.length} segments`);
    asro.dropped = segments.length - kept.length;
    return kept;
}

// let active_channeln = $state(0);
// const un1 = active_channel.subscribe( x => active_channeln = x );

let ldco;

function run_sad(docids, ldc, source_uid_channels){
    // add_which = 'sad';
    // dialog_sad.showModal();
    // add_sad_p = add_sad_send(source_uid, ldc);
    // add_sad_p3 = add_sad_p.then( (data) => {
    //     console.log('adding')
    //     console.log(data);
    //     const f = add_timestamps(data, docids);
    //     f();
    //     add_cb( () => dialog_sad.close() );
    //     return 'displaying segments...';
    // } );
    ldco = ldc;
    // Optional feature: an instance with no HLT_ENDPOINT / PROMISE_BUCKET has
    // nowhere to send the audio. Say so and stop, rather than posting to an
    // empty URL and failing somewhere the annotator can't interpret.
    if(!services_configured()){
        sado.status = 'unavailable';
        return;
    }
    if(sado.status){
        sado.previous = true;
        return;
    }
    sado.i = 0;
    sado.source_uid_channels = source_uid_channels;
    sado.docids = docids;
    run_sad_helper();
}

function run_sad_helper(){
    sado.status = 'pending';
    // sado.pending_promise = new Promise((x,y) => {});
    sado.pending_promise = add_sad_send(sado.source_uid_channels[sado.i], ldco).then(data => {
        console.log('adding')
        console.log(data)
        sado.status = 'adding';
        sado.segments = data;
        const f = add_timestamps(data, sado.docids);
        f();
        return data;
        // return new Promise((x,y) => {});
        return 'displaying segments...';
    });
}
    
function add_timestamps(o, docids) {
    return () => {
        let t;
        let len2;
        for(t = 0, len2 = o.ch1.length; t < len2; t++){
            let x = o.ch1[t];
            let span = {
                offset: x[0],
                length: round_to_6_places(x[1] - x[0])
            };
            // let docid = window.ldc.ns.waveform.docid.replace(/:B$/, ':A');
            add_audio_to_list(docids[0], '.SegmentList', 'new.Segment', span);
        }
        let u;
        let len3;
        for(u = 0, len3 = o.ch2.length; u < len3; u++) {
            let x = o.ch2[u];
            let span = {
                offset: x[0],
                length: round_to_6_places(x[1] - x[0])
            };
            console.log(span);
            // let docid = window.ldc.ns.waveform.docid.replace(/:A$/, ':B');
            add_audio_to_list(docids[1], '.SegmentList', 'new.Segment', span);
        }
        add_audio_to_listq();
    }
}

// `span` bounds what this run may add — { beg, end }, end possibly Infinity.
// Omitted (or null) means the whole recording, which is how this behaved
// before the span prompt and how any caller that doesn't ask still behaves.
function run_asr4(type, docids, ldc, source_uid_channels, span = null){
    ldco = ldc;
    // Optional feature: an instance with no HLT_ENDPOINT / PROMISE_BUCKET has
    // nowhere to send the audio. Say so and stop, rather than posting to an
    // empty URL and failing somewhere the annotator can't interpret.
    if(!services_configured()){
        asro.status = 'unavailable';
        return;
    }
    // Refuse only while a run is actually in flight. `status` stays 'done'
    // after one finishes, so testing it for truthiness rejected every run
    // after the first — silently, since the caller has no way to tell a
    // refusal from a run that found nothing. That is what made asking for ASR
    // a second time do nothing at all.
    if(asro.status && asro.status !== 'done'){
        asro.previous = true;
        return;
    }
    // The per-docid promise cache below stops one run calling the service
    // twice for the same channel; it is not meant to outlive the run. Left in
    // place, a second run was handed the first run's already-resolved promise
    // and the service was never called again.
    asrp.clear();
    asro.type = type;
    asro.span = span;
    asro.dropped = 0;
    // The segment list reads these to show progress while the rows load, so
    // clear them here — otherwise a new run briefly reports the last one's
    // totals, between the keystroke and the service answering.
    asro.vvsegs = [];
    asro.addedn = 0;
    asro.i = 0;
    asro.source_uid_channels = source_uid_channels;
    asro.docids = docids;
    // asro.status = 'init';
    // asro.pending_promise = new Promise((x,y) => {});
    // console.log('calling');
    // asro.pending_promise = cb();
    // asr_store.set(x);
    // asro.promise = cb().then(y => {
    run_asr4_helper();
}

function run_asr4_helper(){
    asro.status = 'pending';
    bulk_start('Running ASR');
    asro.pending_promise = xasr(asro.docids, ldco).then(y => {
        console.log('adding')
        console.log(y)
        asro.status = 'adding';
        bulk_total(asro.vvsegs?.length ?? 0, 'Loading segments');
        // asro.result = y;
        // asr_store.set(x);
        // return new Promise((x,y) => { xasrr(x) });
        // return xasrr(y);
        // return asro;
        xasrr();
        // return `${asro.items.length} items loaded from asr (channel ${asro.i})`;
        return 'displaying segments...';
    }).catch( (e) => {
        // A service that fails leaves status at 'pending', and the progress
        // panel hides the transcript while anything is in flight — so without
        // this the list never comes back and the annotator has to reload.
        // Re-thrown: the dialog reporting the failure reads this rejection.
        asro.status = 'done';
        bulk_end();
        throw e;
    });
}

// let asrp = $state();
// let asro = $state({});

const asrp = new Map();

function xasr(docids, ldc){
//   if(asrp) return asrp;
  const type = asro.type;
  const docid = docids[asro.i];
  const stereo = docid.match(/:A$/);
  if(asrp.has(docid)) return asrp.get(docid);
  asrp.set(docid, Promise.resolve());  // make sure it can't be called twice
  asro.source_uid = asro.source_uid_channels[asro.i];
  let p = add_asr_sendx(docid, type, ldc);
  if(type == 'rev') p = p.then(x => split_word_sequence(x, activeo.channel == asro.i, stereo));
  const mapf = (x) => x == 'ch_1' ? docids[1] : docid;
  // Before xasr_process, which is what turns these into the rows that get
  // added — so a dropped span never becomes a segment, rather than being
  // created and removed.
  p = p.then(filter_to_span);
  p = p.then(x => xasr_process(x, mapf));
  // asrp = add_asr_sendx2(docid);
  asrp.set(docid, p);
  return p;
}

function xasrr(){
    asro.addedn = -1;
    // vvsegs_length = asro.vvsegs.length;
    // i = asro.i;
    const p = new Promise((x,y) => xasrrr(0, asro.vvsegs, x));
    asro.promise = p.then(() => {
        console.log('calling')
        asro.status = 'done';
        bulk_end();
        // x.asro = asro;
        // asr_store.set(x);
        const n = asro.source_uid_channels.length - asro.asr_previous.length;
        if(n > 1){
            asro.asr_previous.push(asro.source_uid_channels[asro.asr_previous.length]);
            // asr_previous.push(x);
            asro.i = asro.asr_previous.length;
            run_asr4_helper();
            // asr_store.set({
            //     type: 'asr4',
            //     status: 'init',
            //     i: asr_previous.length,
            //     previous_run: x
            // });
        }
    });
}

function xasrrr(i, vvsegs, f){
    asro.addedn = i;
    bulk_done(i);
    const max = vvsegs.length;
    // f('done');
    if(i == max){
        // setTimeout( () => asrp = null, 3000 );
        f('done');
        return;
    }
    let j = i;
    while(j < i + BATCH_SIZE && j < max){
        const s = vvsegs[j++];
        // console.log(s);
        add_audio_to_list(s.docid, null, null, s);
    }
    add_audio_to_listq(() => xasrrr(j, vvsegs, f));
}

async function xasr4(type, docid, docids){
        return;
        // if(asrp) return;
        // let a = [];
        // // asro = {};
        // asro.segments = [];
        // asro.items = [];//.results.items;
        // asrp =     xasr44(                0, d, '_AB.wav', type, (x) => x == 'ch_1' ? docids[1] : docids[0])
        // .then(x => xasr44(asro.items.length, d, '_CD.wav', type, (x) => x == 'ch_1' ? docids[3] : docids[2]));

        // if(debug) console.log(asro);
        // if(asro.error) console.error(asro.error);
        // else           asro.show = true;
        // // sort_segments();
        // console.log(vvsegs);
        // return asrp;
    }

    async function xasr44(asro_i, x, y, type, mapf){
        let a = await add_asr_sendx(x.replace(/.wav:[ABCD]/, y), type);
        for(let i = 0; i < a.length; i++) asro.items.push(a[i]);
        let check = 0;
        while(asro_i < asro.items.length){
            check++;
            asro_i = xasr2(asro_i, mapf);
            // console.log(asro_i)
            if(check > 10000) break;
        }
    }


export {
    asro,
    sado,
    run_sad,
    run_asr4,
    xasrr
}
