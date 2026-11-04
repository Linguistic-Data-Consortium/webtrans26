import { add_sad_send } from './helpers';
import { split_word_sequence, add_asr_sendx, xasr_process } from './services';
import { services_configured } from '../service_config';
import { local_audio_active } from '../local_audio';
import { local_asr_available, run_local_asr_for, single_pass_on, asr_model, run_language } from '../local_asr';
import { language_name } from '../whisper_languages';
import { add_layer } from './span_layers.svelte';
import { rows_to_spans, stretch_label } from './spans';
import { energy_available, run_energy_segments_for } from './energy_run';
import { drop_overlapping } from './spans';
import { transcript } from './transcript.svelte';
import { activeo } from './shared.svelte';
import { BATCH_SIZE, bulk_start, bulk_total, bulk_done, bulk_end } from './bulk.svelte';
import { transcribe_stretch } from './segment_asr_run';
import { download_tracker } from './segment_asr';
import { round_to_6_places } from './times';
import {
    add_audio_to_list,
    add_audio_to_listq
} from './modification1';
import { toast } from 'svelte-sonner';

// (Landed in f447775; described in the commit after it.)
// What a run says, now that progress shows where the transcript is (the bulk
// panel) rather than in a dialog over it: a refusal, a failure and how a run
// went are toasts.
const REFUSALS = {
    unavailable:     'Speech activity detection and ASR are not configured on this server, so they are unavailable.',
    local_audio:     "This kit's audio is a file on your computer, and it stays there, so the speech services on the server are unavailable for it. Recognition that runs in this browser still works.",
    no_local_engine: 'This browser cannot run speech recognition on its own — it has no Web Worker or no audio decoding.',
    no_decoder:      "This browser cannot decode audio on its own, so segments can't be found from the sound level here.",
    busy:            'A run is already in progress; it has to finish first.'
};
function refuse(kind){
    toast.info(REFUSALS[kind]);
}

const RUN_NAMES = { asr4: 'ASR', asr6: 'ASR (Korean)', rev: 'ASR (Rev.ai)', local: 'in-browser ASR', energy: 'sound level' };

// ── Preview: a run's results as a span layer, not segments ───────────────
//
// What a run finds is shown under the waveform (span_layers.svelte.js) and
// saved as nothing; the lane's add buttons turn it into segments when wanted,
// text and all. Asked for in the run's dialog, beside Add segments — the
// pair sound-level segmentation has.

function short_model(id){
    return String(id).replace(/^.*\//, '');
}
const plural = (n, one) => `${n} ${one}${n == 1 ? '' : 's'}`;
const db = (x) => x == null ? '–' : `${Math.round(x)} dB`;

// How a run went, once its last channel is in.
function summarize_run(){
    if(asro.type == 'energy'){
        const parts = (asro.energy || []).map( (e) => {
            let t = `background about ${db(e.floor)}, segments above ${db(e.threshold)}: found ${e.found}`;
            if(e.skipped) t += `, skipped ${e.skipped} that overlapped existing segments`;
            if(e.rejected?.not_enough_sound) t += `, rejected ${e.rejected.not_enough_sound} as mostly background (clicks)`;
            if(e.rejected?.too_spread) t += `, rejected ${e.rejected.too_spread} as too uneven (knocks)`;
            return (asro.energy.length > 1 ? `${e.docid}: ` : '') + t;
        } );
        return `Sound level — ${parts.join('; ')}.`;
    }
    let t = `${plural(asro.added_total ?? 0, 'segment')} added from ${RUN_NAMES[asro.type] ?? asro.type}`;
    if(asro.dropped_total) t += `; ${asro.dropped_total} outside the stretch asked for were left out`;
    if(asro.type == 'local') t += local_timing();
    return `${t}.`;
}
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

// `span` bounds what it may make ({ beg, end }, end possibly Infinity);
// `preview` makes it a span layer rather than segments.
function run_sad(docids, ldc, source_uid_channels, span = null, { preview = false } = {}){
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
    // A local_audio kit's file never leaves the annotator's computer, and
    // both services work by sending it to one.
    if(local_audio_active()){
        sado.status = 'local_audio';
        return refuse('local_audio');
    }
    if(!services_configured()){
        sado.status = 'unavailable';
        return refuse('unavailable');
    }
    // In flight only. This tested any status at all, and nothing ever reset
    // it, so a second SAD run on the same page was refused — which the dialog
    // used to say; with progress in the panel it would have been silent.
    if(sado.status == 'pending' || sado.status == 'adding'){
        sado.previous = true;
        return refuse('busy');
    }
    sado.i = 0;
    sado.source_uid_channels = source_uid_channels;
    sado.docids = docids;
    sado.span = span;
    sado.preview = preview;
    run_sad_helper();
}

// The service answers with spans per channel (ch1, ch2), added in batches
// behind the progress panel like any other run.
function run_sad_helper(){
    sado.status = 'pending';
    bulk_start('Running speech activity detection');
    sado.pending_promise = add_sad_send(sado.source_uid_channels[sado.i], ldco).then( (data) => {
        sado.status = 'adding';
        sado.segments = data;
        const beg = sado.span?.beg ?? 0, end = sado.span?.end ?? Infinity;
        const spans = sad_spans(data, sado.docids)
            .filter( (s) => s.offset >= beg && s.offset + s.length <= end );
        if(sado.preview){
            return add_layer({
                label: `Speech activity detection${stretch_label(sado.span)}`,
                source: 'sad',
                segments: rows_to_spans(spans)
            }).then( (layer) => ({ preview: layer }) );
        }
        bulk_total(spans.length, 'Adding segments');
        return new Promise( (resolve) => add_sad_batch(0, spans, resolve) ).then( () => ({ added: spans.length }) );
    } ).then( (r) => {
        sado.status = 'done';
        bulk_end();
        if(r.preview) toast.success(`Preview: ${plural(r.preview.segments.length, 'span')} from speech activity detection, shown under the waveform. Nothing was added.`);
        else          toast.success(`${plural(r.added, 'segment')} added from speech activity detection.`);
    } ).catch( (e) => {
        sado.status = 'done';
        bulk_end();
        toast.error(`Speech activity detection failed: ${e?.message || e}`);
    } );
}

function sad_spans(o, docids){
    const out = [];
    for(const [ list, docid ] of [ [ o?.ch1, docids[0] ], [ o?.ch2, docids[1] ] ]){
        if(!list || !docid) continue;
        for(const x of list) out.push({ docid, offset: x[0], length: round_to_6_places(x[1] - x[0]) });
    }
    return out;
}

function add_sad_batch(i, spans, done){
    bulk_done(i);
    if(i >= spans.length) return done();
    let j = i;
    while(j < i + BATCH_SIZE && j < spans.length){
        const s = spans[j++];
        add_audio_to_list(s.docid, '.SegmentList', 'new.Segment', s);
    }
    add_audio_to_listq( () => add_sad_batch(j, spans, done) );
}
    
// `span` bounds what this run may add — { beg, end }, end possibly Infinity.
// Omitted (or null) means the whole recording, which is how this behaved
// before the span prompt and how any caller that doesn't ask still behaves.
//
// `params` is for type 'energy' only: energy_segments.js's parameters.
// `preview` makes the run a span layer rather than segments.
function run_asr4(type, docids, ldc, source_uid_channels, span = null, params = null, { preview = false } = {}){
    ldco = ldc;
    // 'local' runs the model in this browser, so neither refusal below
    // applies to it: there is nothing to configure and nothing to send. What
    // it needs instead is a browser that can run it at all.
    if(type == 'local'){
        if(!local_asr_available()){
            asro.status = 'no_local_engine';
            return refuse('no_local_engine');
        }
    }
    // Segments from sound level: measured in this browser too, and needs only
    // a way to decode audio.
    else if(type == 'energy'){
        if(!energy_available()){
            asro.status = 'no_decoder';
            return refuse('no_decoder');
        }
    }
    // A local_audio kit's file never leaves the annotator's computer, and
    // every *hosted* service works by sending it to one. The local type above
    // is the exception, which is why this is no longer the last word on ASR
    // for such a kit.
    else if(local_audio_active()){
        asro.status = 'local_audio';
        return refuse('local_audio');
    }
    // Optional feature: an instance with no HLT_ENDPOINT / PROMISE_BUCKET has
    // nowhere to send the audio. Say so and stop, rather than posting to an
    // empty URL and failing somewhere the annotator can't interpret.
    else if(!services_configured()){
        asro.status = 'unavailable';
        return refuse('unavailable');
    }
    // Refuse only while a run is actually in flight. `status` stays 'done'
    // after one finishes, so testing it for truthiness rejected every run
    // after the first — silently, since the caller has no way to tell a
    // refusal from a run that found nothing. That is what made asking for ASR
    // a second time do nothing at all.
    if(asro.status == 'pending' || asro.status == 'adding'){
        asro.previous = true;
        return refuse('busy');
    }
    // The per-docid promise cache below stops one run calling the service
    // twice for the same channel; it is not meant to outlive the run. Left in
    // place, a second run was handed the first run's already-resolved promise
    // and the service was never called again.
    asrp.clear();
    asro.type = type;
    asro.span = span;
    asro.params = params;
    asro.energy = [];
    asro.dropped = 0;
    asro.added_total = 0;
    asro.dropped_total = 0;
    asro.preview = preview && type != 'energy';
    asro.preview_spans = [];
    asro.local_timing = null;
    asro.asr_previous = [];
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

// A local run has stages a service call does not: the audio is decoded, the
// model may have to be downloaded and is then built, and only then is anything
// transcribed. Each stage goes in the panel's label — the panel counts
// segments, and the download's byte counts put there read as millions of
// them. The download is one percentage over all the model's files; from the
// browser's cache it reports every file at 100% at once, which reads as
// loading, so it says so.
//
// The stages are timed too, for the summary: how long the model took to be
// ready, how long transcribing took, and on which backend — what decides
// whether a slow run wants a different model, quantisation or browser.
let local_run = null;

function local_progress(m){
    const r = local_run;
    if(!r) return;
    if(m.stage == 'decoding')           bulk_total(0, 'Reading the audio');
    else if(m.stage == 'downloading'){
        const p = r.pct(m);
        bulk_total(0, p != null && p < 100 ? `Downloading the speech model (${p}%)` : 'Loading the speech model');
    }
    else if(m.stage == 'transcribing'){
        r.ready ??= Date.now();
        r.device = m.device ?? r.device;
        const part = !(m.total > 1) ? ''
            : m.done >= m.total ? ' (putting the parts together)'
            : ` (part ${(m.done ?? 0) + 1} of ${m.total})`;
        bulk_total(0, `Transcribing in this browser${part}`);
    }
    else if(m.stage == 'done'){
        r.finished = Date.now();
        r.device = m.device ?? r.device;
        r.timing = m.timing ?? null;
    }
    else if(m.stage)                    bulk_total(0, 'Loading the speech model');
}

const secs = (ms) => `${Math.max(0, Math.round(ms / 100) / 10)} s`;
const tenths = (ms) => `${Math.max(0, Math.round(ms / 100) / 10)}`;
const BACKENDS = { webgpu: 'WebGPU', wasm: 'WASM' };

// "model ready in 8.2 s; transcribing took 41.5 s on WASM: windows 8.1, 8.3,
// 8.0, 8.2, 8.4 s (10 passes), joining 0.2 s; adding took 0.4 s", summed over
// the channels a run went through — every stage a run spends time in, so a slow
// one says where. Passes are shown when there were more than windows:
// Whisper's seek loop going round again inside a window.
function local_timing(){
    const t = asro.local_timing;
    if(!t || !t.transcribing) return '';
    const on = (t.device ? ` on ${BACKENDS[t.device] ?? t.device}` : '') + (t.single_pass ? ', one pass per window' : '');
    const passes = t.passes > t.windows.length ? ` (${t.passes} passes)` : '';
    const parts = t.windows.length > 1 || t.merge
        ? `: windows ${t.windows.map(tenths).join(', ')} s${passes}, joining ${secs(t.merge)}` : '';
    const adding = t.adding != null ? `; adding took ${secs(t.adding)}` : '';
    return ` (model ready in ${secs(t.loading)}; transcribing took ${secs(t.transcribing)}${on}${parts}${adding})`;
}

function run_asr4_helper(){
    asro.status = 'pending';
    bulk_start(asro.type == 'local'  ? 'Transcribing in this browser'
             : asro.type == 'energy' ? 'Measuring the sound level'
             :                         'Running ASR');
    asro.pending_promise = xasr(asro.docids, ldco).then(y => {
        console.log('adding')
        console.log(y)
        if(asro.preview){
            asro.preview_spans.push(...rows_to_spans(asro.vvsegs || []));
            asro.dropped_total = (asro.dropped_total ?? 0) + (asro.dropped ?? 0);
            asro.status = 'done';
            bulk_end();
            next_channel_or_finish();
            return;
        }
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
        asro.status = 'done';
        bulk_end();
        toast.error(`${RUN_NAMES[asro.type] ?? 'The run'} failed: ${e?.message || e}`);
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
  if(type == 'energy') return energy_segments_for(docid, docids, ldc);
  if(type == 'local'){
    local_run = { start: Date.now(), pct: download_tracker(), ready: null, finished: null, device: null, single_pass: single_pass_on() };
    asro.local_model = asr_model();
    asro.local_language = run_language(asro.local_model);
  }
  // A stretch asked for is all that's transcribed in the browser (the hosted
  // services take the whole file and are filtered below); the whole
  // recording goes as it always has.
  const bounded = asro.span && (asro.span.beg > 0 || asro.span.end !== Infinity);
  const local = () => bounded
      ? transcribe_stretch(docid, asro.span, { ldc, docids, source_uid_channels: asro.source_uid_channels, onprogress: local_progress })
      : run_local_asr_for(docid, ldc, { onprogress: local_progress });
  let p = type == 'local'
      ? local().then( (segments) => {
            const r = local_run;
            if(r?.ready){
                const t = asro.local_timing ??= { loading: 0, transcribing: 0, device: null, windows: [], passes: 0, merge: 0, adding: null };
                t.loading += r.ready - r.start;
                t.transcribing += (r.finished ?? Date.now()) - r.ready;
                t.device = r.device ?? t.device;
                t.windows.push(...(r.timing?.windows ?? []));
                t.merge += r.timing?.merge ?? 0;
                t.passes += r.timing?.passes ?? 0;
                t.single_pass = r.single_pass;
            }
            return segments;
        } )
      : add_asr_sendx(docid, type, ldc);
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

// One source file's segments from sound level, as rows ready to add. Its own
// path through xasr because two things differ from a transcript: channels map
// to docids by number (a stereo file's channels are measured together, where a
// service returns ch_0/ch_1), and only gaps are filled — anything touching an
// existing segment on the same channel is skipped.
function energy_segments_for(docid, docids, ldc){
  // A kit whose channels are separate files measures each file's first
  // channel; one file with several channels measures as many as it has docids.
  const separate = asro.source_uid_channels.length > 1;
  const channels = separate ? 1 : Math.max(1, docids.length);
  const docid_of = (s) => {
    const n = Number(s.channel.replace('ch_', ''));
    return n > 0 && !separate && docids[n] ? docids[n] : docid;
  };
  const progress = (m) => {
    bulk_total(m.total, 'Measuring the sound level');
    bulk_done(m.done);
  };
  const p = run_energy_segments_for(asro.source_uid, ldc, { span: asro.span, params: asro.params, channels, onprogress: progress })
    .then( (per_channel) => {
      const rows = per_channel.flatMap( (r, c) => {
        const segs = r.segments.map( (x) => ({ ...x, text: '', channel: `ch_${c}` }) );
        const { kept, skipped } = drop_overlapping(segs, transcript.segments, docid_of);
        asro.energy.push({ docid: docid_of({ channel: `ch_${c}` }), floor: r.floor, threshold: r.threshold,
                           found: segs.length, skipped, rejected: r.rejected });
        return kept;
      } );
      return xasr_process(rows, (channel) => docid_of({ channel }));
    } );
  asrp.set(docid, p);
  return p;
}

function xasrr(){
    asro.addedn = -1;
    // vvsegs_length = asro.vvsegs.length;
    // i = asro.i;
    const adding_from = Date.now();
    const p = new Promise((x,y) => xasrrr(0, asro.vvsegs, x));
    asro.promise = p.then(() => {
        if(asro.local_timing) asro.local_timing.adding = (asro.local_timing.adding ?? 0) + (Date.now() - adding_from);
        asro.added_total = (asro.added_total ?? 0) + (asro.vvsegs?.length ?? 0);
        asro.dropped_total = (asro.dropped_total ?? 0) + (asro.dropped ?? 0);
        asro.status = 'done';
        bulk_end();
        next_channel_or_finish();
    });
}

// On to the next source file, if the kit's channels are separate files, or
// say how the run went.
function next_channel_or_finish(){
    const n = asro.source_uid_channels.length - asro.asr_previous.length;
    if(n > 1){
        asro.asr_previous.push(asro.source_uid_channels[asro.asr_previous.length]);
        asro.i = asro.asr_previous.length;
        run_asr4_helper();
    }
    else if(asro.preview) finish_preview();
    else toast.success(summarize_run());
}

// Every channel in: one layer for the run, named by what made it.
function finish_preview(){
    const name = RUN_NAMES[asro.type] ?? asro.type;
    const lang = asro.local_language ? `, ${language_name(asro.local_language)}` : '';
    const model = asro.type == 'local' ? ` (${short_model(asro.local_model ?? asr_model())}${lang})` : '';
    let note = asro.type == 'local' ? local_timing().replace(/^ \(|\)$/g, '') : '';
    if(asro.dropped_total) note = [ note, `${asro.dropped_total} outside the stretch left out` ].filter(Boolean).join('; ');
    const spans = asro.preview_spans;
    add_layer({
        label: `${name.charAt(0).toUpperCase()}${name.slice(1)}${model}${stretch_label(asro.span)}`,
        source: asro.type,
        params: asro.type == 'local' ? { model: asro.local_model ?? asr_model(), language: asro.local_language ?? 'en', single_pass: !!asro.local_timing?.single_pass } : null,
        note: note || null,
        segments: spans
    }).then( (layer) => {
        toast.success(`Preview: ${plural(layer.segments.length, 'span')} from ${name}${note ? ` (${note})` : ''}, shown under the waveform. Nothing was added.`);
    }, (e) => toast.error(`Couldn't keep the preview: ${e?.message || e}`) );
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
