// Reading a recording's sound level, for energy_segments.js.
//
// Decoded a piece at a time, the way the waveform draws (channel.svelte's
// get_audio_buffer): the file's own header in front of a byte range of its
// data, handed to decodeAudioData. So memory stays at one piece however long
// the recording is, and any format the waveform can show can be measured — a
// local_audio file too, since its ranges are read off the File (getp.js).
//
// The loop itself is segment_audio in energy_segments.js, which takes its
// reading and decoding as functions; this wires in the real ones.

import { segment_audio, selection_stats, remembered_params } from './energy_segments';
import { ParseB } from './parse_b';
import { set_urls_source } from './helpers';
import { local_file_for, read_local_range } from '../local_audio';

// Bytes b..e inclusive, refusing rather than returning nothing: getp_wav
// swallows its errors, and a measurement that silently skipped pieces would
// report silence where there was speech.
async function read_range(url, b, e){
    const file = local_file_for(url);
    if(file) return read_local_range(file, b, e);
    const r = await fetch(url, { headers: { range: `bytes=${b}-${e}` } });
    if(!r.ok) throw new Error(`could not read the audio (HTTP ${r.status})`);
    const buf = await r.arrayBuffer();
    // A host that ignores Range sends the whole file with a 200.
    return r.status == 200 && buf.byteLength > e - b + 1 ? buf.slice(b, e + 1) : buf;
}

function offline_context_class(){
    if(typeof window === 'undefined') return undefined;
    return window.OfflineAudioContext || window.webkitOfflineAudioContext;
}

export function energy_available(){
    return typeof offline_context_class() === 'function';
}

// One source file of the open kit, ready to be read a range at a time:
// `read(b, e)` for bytes b..e inclusive, ParseB's `info`, and the header's own
// bytes to put in front of any range of the data before decoding it. Shared
// with segment_asr.js, which reads a segment at a time the same way.
export async function open_audio(source_uid, ldc){
    const o = await set_urls_source(source_uid, ldc);
    const url = o?.wav_url;
    if(!url) throw new Error(`no audio url for ${source_uid}`);
    const first = await read_range(url, 0, 8191);
    const info = new ParseB('audio').parse(first);
    const header = await read_range(url, 0, info.dataOffset - 1);
    return { read: (b, e) => read_range(url, b, e), info, header };
}

// `channels` caps how many of the file's channels become segments — those the
// kit has docids for.
export async function run_energy_segments_for(source_uid, ldc, { span, params, channels, onprogress }){
    const { read, info, header } = await open_audio(source_uid, ldc);
    const Ctx = offline_context_class();
    if(!Ctx) throw new Error('this browser cannot decode audio here');
    // At the file's own rate, so decoding doesn't resample.
    const ctx = new Ctx(1, 1, info.sample_rate);
    const decode = async (buf) => {
        const audio = await ctx.decodeAudioData(buf);
        return Array.from({ length: audio.numberOfChannels }, (_, c) => audio.getChannelData(c));
    };
    return segment_audio({ read, decode }, { info, header, span, params, channels, onprogress });
}

// Statistics on beg..end of the open kit, a row per channel:
// [ { docid, ...selection_stats } ]. Channels map to docids as a sound-level
// run maps them — a docid per file where the channels are separate files, a
// docid per channel of one file otherwise.
//
// Also what a sound-level run with the settings last used here would see.
export async function run_selection_stats({ beg, end, ldc, docids, source_uid_channels, onprogress = null, params = remembered_params() }){
    const Ctx = offline_context_class();
    if(!Ctx) throw new Error('this browser cannot decode audio here');
    const separate = source_uid_channels.length > 1;
    const sources = separate ? source_uid_channels : [ source_uid_channels[0] ];
    const rows = [];
    for(let f = 0; f < sources.length; f++){
        const { read, info, header } = await open_audio(sources[f], ldc);
        const ctx = new Ctx(1, 1, info.sample_rate);
        const decode = async (buf) => {
            const audio = await ctx.decodeAudioData(buf);
            return Array.from({ length: audio.numberOfChannels }, (_, c) => audio.getChannelData(c));
        };
        const per_channel = await selection_stats({ read, decode }, {
            info, header, beg, end, onprogress, params,
            channels: separate ? 1 : Math.max(1, docids.length)
        });
        per_channel.forEach( (r, c) => rows.push({ docid: separate ? docids[f] : (docids[c] ?? docids[0]), ...r }) );
    }
    return rows;
}

