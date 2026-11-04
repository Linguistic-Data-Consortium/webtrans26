// In-browser ASR one segment at a time: the text of segments that already
// exist, rather than new segments from a whole recording.
//
// The segments decide what is transcribed and where its text goes, so nothing
// is created, moved or split — only a Text label changed, the same message the
// textarea sends. That is why it is allowed on transcribe_text_only kits.
//
// Text is only ever written where there was none: a segment is checked again
// at the moment its text is written, so anything typed while recognition ran
// is kept. Each segment's audio is read on its own, as the file's header in
// front of that segment's bytes (energy_run.js's open_audio), so a long
// recording isn't decoded to transcribe a few lines of it.
//
// Pure: the reading, decoding and recognising are passed in.
// segment_asr_run.js wires in the real ones.

// A segment with no text yet, that has times, and that is the annotator's
// (not a reference caption or a virtual row).
export function is_empty_segment(row){
    return row && !row.readonly && !row.virtual
        && row.beg != null && row.end != null && row.end > row.beg
        && String(row.text ?? '').trim() === '';
}

// What a batch run over `span` ({ beg, end }, end possibly Infinity) does:
// the empty segments that fit entirely inside it, in time order — the same
// "fits inside" the ASR span uses.
export function rows_to_transcribe(rows, span = null){
    const beg = span?.beg ?? 0;
    const end = span?.end ?? Infinity;
    return rows
        .filter( (r) => is_empty_segment(r) && r.beg >= beg && r.end <= end )
        .sort( (a, b) => a.beg - b.beg );
}

// Which file, and which channel of it, a segment's docid is. A kit whose
// channels are separate files has one docid per file; one file with several
// channels has one docid per channel (…:A, …:B).
export function source_for(docid, docids, source_uid_channels){
    const i = Math.max(0, docids.indexOf(docid));
    if(source_uid_channels.length > 1) return { source_uid: source_uid_channels[i] ?? source_uid_channels[0], channel: 0 };
    return { source_uid: source_uid_channels[0], channel: i };
}

// A segment's audio as a file decodeAudioData accepts: the header, then the
// sample frames from beg to end.
export async function segment_bytes({ read, info, header }, beg, end){
    const total = Math.floor(info.dataSize / info.blockSize);
    const s0 = Math.max(0, Math.floor(beg * info.sample_rate));
    const s1 = Math.min(total, Math.ceil(end * info.sample_rate));
    if(s1 <= s0) throw new Error(`no audio between ${beg} and ${end}`);
    const bytes = await read(info.dataOffset + s0 * info.blockSize, info.dataOffset + s1 * info.blockSize - 1);
    const whole = new Uint8Array(header.byteLength + bytes.byteLength);
    whole.set(new Uint8Array(header), 0);
    whole.set(new Uint8Array(bytes), header.byteLength);
    return whole.buffer;
}

// Transcribe `rows` one after another and write each one's text.
//
//   samples_for(row)   → 16 kHz mono Float32Array of the segment
//   session            { transcribe(samples) → text }
//   write(row, text)   → true if written; false when the segment has text
//                        by now, which is then counted as skipped
//   signal             an AbortSignal: stops before the next segment
//   onprogress(done, total)
//
// A segment that fails is reported and the run goes on; one bad stretch of
// audio shouldn't cost the rest. Resolves with what happened:
// { written, nothing_heard, skipped, failed: [ { row, message } ], cancelled }.
export async function transcribe_rows(rows, { samples_for, session, write, signal = null, onprogress = null }){
    const out = { written: 0, nothing_heard: 0, skipped: 0, failed: [], cancelled: false };
    onprogress?.(0, rows.length);
    for(let i = 0; i < rows.length; i++){
        if(signal?.aborted){ out.cancelled = true; break; }
        const row = rows[i];
        try {
            const text = await session.transcribe(await samples_for(row));
            if(signal?.aborted){ out.cancelled = true; break; }
            if(!text)                    out.nothing_heard++;
            else if(await write(row, text)) out.written++;
            else                         out.skipped++;
        }
        catch(e){
            if(signal?.aborted){ out.cancelled = true; break; }
            out.failed.push({ row, message: e?.message || String(e) });
        }
        onprogress?.(i + 1, rows.length);
    }
    return out;
}

// One line for the annotator about how a run went.
export function summarize(r){
    const parts = [];
    parts.push(`${r.written} segment${r.written == 1 ? '' : 's'} transcribed`);
    if(r.nothing_heard) parts.push(`${r.nothing_heard} with no speech recognised`);
    if(r.skipped)       parts.push(`${r.skipped} skipped because text was typed meanwhile`);
    if(r.failed.length) parts.push(`${r.failed.length} failed (${r.failed[0].message})`);
    return (r.cancelled ? 'Stopped: ' : '') + parts.join(', ') + '.';
}

// The model arrives as several files at once, and each progress message is
// about one of them — so a percentage taken from any single message jumps
// between files (100%, 9%, 87%…). This keeps every file's latest numbers and
// answers for all of them together, or null before any total is known.
export function download_tracker(){
    const files = new Map();
    return (m) => {
        if(m?.stage != 'downloading' || !m.total) return null;
        files.set(m.file ?? '', { loaded: m.loaded || 0, total: m.total });
        let loaded = 0, total = 0;
        for(const f of files.values()){ loaded += f.loaded; total += f.total; }
        return Math.min(100, Math.round(100 * loaded / total));
    };
}

// ASR suggestions (asr_preview.svelte.js): which segments to have ready — the
// first `n` empty ones from `start` (an index into the list in display order),
// the active segment included. Ahead of the annotator, so a suggestion is
// usually waiting by the time they reach it.
export function rows_ahead(rows, start, n){
    const out = [];
    for(let i = Math.max(0, start ?? 0); i < rows.length && out.length < n; i++){
        if(is_empty_segment(rows[i])) out.push(rows[i]);
    }
    return out;
}

// A suggestion is for one segment at its times: moved or resized, the audio
// is different and the old text doesn't apply.
export function suggestion_key(row){
    return `${row.iid}@${row.beg}-${row.end}`;
}

