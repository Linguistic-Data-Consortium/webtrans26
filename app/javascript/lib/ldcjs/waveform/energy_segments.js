// Segments from sound level: where the audio rises above its own background.
//
// No model and no service — the level of the recording in short frames, a
// noise floor estimated from the quietest of them, and a threshold a margin
// above that floor. Adaptive rather than a fixed dB value, because recordings
// differ by tens of dB in gain and hiss and one number would suit none of
// them.
//
// Everything here is pure: levels in, segments out. energy_run.js does the
// reading and decoding, and asr.svelte.js adds the result through the same
// batched path as every ASR run.

// One level per FRAME_SECONDS of audio. 20 ms is short enough to place a
// boundary well and long enough that a single frame isn't noise.
export const FRAME_SECONDS = 0.02;

// What the annotator sees prefilled. All in seconds except margin_db.
export const DEFAULTS = Object.freeze({
    margin_db: 10,      // how far above the noise floor counts as sound
    min_silence: 0.3,   // a quieter gap shorter than this doesn't end a segment
    min_segment: 0.3,   // sound shorter than this is a click, not a segment
    padding: 0.1,       // added at each edge, so a segment doesn't clip a word
    max_segment: 15,    // longer is split at its quietest point; null for no limit
    // Clicks and other impulses (sound_measures): a segment at least this
    // much of which is sound — frames above the end threshold — or it's
    // rejected. 50 is "the median frame is sound". A click train is mostly
    // background joined across short gaps; speech, even with pauses, mostly
    // isn't (measured: speech 70–99 %, click trains 9–31 %).
    min_sound_pct: 50,
    // ...and, if set, at most this spread (Q3 − Q1, dB) among those sound
    // frames: a knock decays steadily, speech holds its level. null is off —
    // calibrate it on real recordings (Selection statistics shows it) first.
    max_sound_spread: null
});

// The keys that may be left blank to mean "no limit" rather than the default.
const OFF_WHEN_BLANK = new Set([ 'max_segment', 'max_sound_spread' ]);

// The end threshold sits this far below the start one, so a level hovering at
// the threshold doesn't open and close a segment frame after frame.
const HYSTERESIS_DB = 3;

// Frames this quiet are digital silence (or near it), not background noise.
// Left in, a recording with silent leader would put the floor at the bottom
// of the scale and call its hiss speech.
const SILENCE_DB = -90;

// How much of a stretch of frame levels is sound — at or above `off`, the end
// threshold — and how spread those sound frames are (Q3 − Q1, dB; 0 with
// fewer than 4 of them, too few for quartiles to mean anything).
export function sound_measures(levels, off){
    const sound = Array.from(levels).filter( (l) => l >= off ).sort( (a, b) => a - b );
    const n = levels.length;
    return {
        share: n ? sound.length / n : 0,
        spread: sound.length >= 4 ? quantile(sound, 0.75) - quantile(sound, 0.25) : 0
    };
}

// The floor is the level the quietest 15% of the frames are below. A low
// percentile rather than the minimum, which is one unlucky frame.
const FLOOR_PERCENTILE = 0.15;

// RMS level in dB of each frame of `samples`.
export function frame_levels(samples, frame_len){
    const n = Math.ceil(samples.length / frame_len);
    const out = new Float32Array(n);
    for(let f = 0; f < n; f++){
        const a = f * frame_len;
        const b = Math.min(a + frame_len, samples.length);
        let sum = 0;
        for(let i = a; i < b; i++) sum += samples[i] * samples[i];
        out[f] = 10 * Math.log10(sum / (b - a) + 1e-10);
    }
    return out;
}

export function noise_floor(levels){
    const sound = Array.from(levels).filter( (l) => l > SILENCE_DB ).sort( (a, b) => a - b );
    if(sound.length == 0) return SILENCE_DB;
    return sound[Math.floor(FLOOR_PERCENTILE * (sound.length - 1))];
}

const round3 = (x) => Math.round(x * 1000) / 1000;

// `levels` covers [offset, offset + levels.length * frame_seconds), clipped to
// `duration`. Returns { floor, threshold, segments: [ { beg, end } ] } in
// seconds from the start of the recording.
export function segments_from_levels(levels, opts = {}){
    const {
        frame_seconds = FRAME_SECONDS,
        offset = 0,
        duration = offset + levels.length * frame_seconds,
        params = DEFAULTS
    } = opts;
    const p = { ...DEFAULTS, ...params };
    const floor = noise_floor(levels);
    const on = floor + p.margin_db;
    const off = on - HYSTERESIS_DB;

    // Runs of sound, in frames [s, e).
    let runs = [];
    let start = -1;
    for(let f = 0; f < levels.length; f++){
        if(start < 0){
            if(levels[f] >= on) start = f;
        }
        else if(levels[f] < off){
            runs.push([ start, f ]);
            start = -1;
        }
    }
    if(start >= 0) runs.push([ start, levels.length ]);

    const frames = (sec) => Math.round(sec / frame_seconds);

    // A short pause inside speech is part of it.
    const merged = [];
    for(const r of runs){
        const last = merged[merged.length - 1];
        if(last && r[0] - last[1] < frames(p.min_silence)) last[1] = r[1];
        else merged.push([ r[0], r[1] ]);
    }
    runs = merged.filter( ([ s, e ]) => e - s >= frames(p.min_segment) );

    if(p.max_segment) runs = runs.flatMap( (r) => split_long(r, levels, frames(p.max_segment), frames(p.min_segment)) );

    // Clicks and impulses out, judged on each segment's own frames, before
    // padding — the short pauses joined into it included, which is what gives
    // a click train away: mostly background, sound only at the clicks.
    const rejected = { not_enough_sound: 0, too_spread: 0 };
    runs = runs.filter( ([ s, e ]) => {
        const m = sound_measures(levels.slice(s, e), off);
        if(m.share * 100 < (p.min_sound_pct ?? 0)){ rejected.not_enough_sound++; return false; }
        if(p.max_sound_spread != null && m.spread > p.max_sound_spread){ rejected.too_spread++; return false; }
        return true;
    } );

    // Padded, then kept apart: where two padded segments would overlap — a
    // split, or a gap shorter than twice the padding — they meet in the middle.
    const span_end = duration;
    const segs = runs.map( ([ s, e ]) => ({
        beg: Math.max(offset, offset + s * frame_seconds - p.padding),
        end: Math.min(span_end, offset + e * frame_seconds + p.padding)
    }) );
    for(let i = 1; i < segs.length; i++){
        if(segs[i].beg < segs[i - 1].end){
            const mid = (segs[i].beg + segs[i - 1].end) / 2;
            segs[i - 1].end = mid;
            segs[i].beg = mid;
        }
    }
    const segments = segs
        .map( (x) => ({ beg: round3(x.beg), end: round3(x.end) }) )
        .filter( (x) => x.end > x.beg );
    return { floor, threshold: on, segments, rejected };
}

// Cut a run longer than `max` frames at its quietest frame, again and again,
// never leaving a piece shorter than `min` frames — so a long stretch of
// speech breaks at its pauses rather than mid-word.
export function split_long(run, levels, max, min){
    const [ s, e ] = run;
    if(e - s <= max) return [ run ];
    const lo = s + Math.max(min, 1);
    const hi = e - Math.max(min, 1);
    if(hi <= lo) return [ run ];
    let cut = lo;
    for(let f = lo; f < hi; f++) if(levels[f] < levels[cut]) cut = f;
    return [ ...split_long([ s, cut ], levels, max, min), ...split_long([ cut, e ], levels, max, min) ];
}

// The dialog's fields, as typed, into parameters — or what's wrong with them.
// Blank max_segment means no limit; any other blank means the default.
export function parse_params(fields){
    const p = {};
    for(const k of Object.keys(DEFAULTS)){
        const raw = String(fields[k] ?? '').trim();
        if(raw === ''){
            p[k] = OFF_WHEN_BLANK.has(k) ? null : DEFAULTS[k];
            continue;
        }
        const v = Number(raw);
        if(Number.isNaN(v)) return { error: `${LABELS[k]} needs to be a number` };
        p[k] = v;
    }
    if(p.margin_db <= 0)                               return { error: 'the margin has to be above zero' };
    if(p.min_silence < 0 || p.min_segment < 0 || p.padding < 0) return { error: "times can't be negative" };
    if(p.max_segment != null && p.max_segment < 2 * p.min_segment) return { error: 'the maximum has to be at least twice the minimum segment' };
    if(p.min_sound_pct < 0 || p.min_sound_pct > 100)  return { error: 'the share that must be sound is a percentage, 0 to 100' };
    if(p.max_sound_spread != null && p.max_sound_spread <= 0) return { error: 'the spread limit has to be above zero, or blank for none' };
    return { params: p };
}

export const LABELS = Object.freeze({
    margin_db: 'Margin above background (dB)',
    min_silence: 'Shortest pause that ends a segment (s)',
    min_segment: 'Shortest segment (s)',
    padding: 'Padding at each edge (s)',
    max_segment: 'Longest segment (s)',
    min_sound_pct: 'Least of a segment that is sound (%)',
    max_sound_spread: 'Largest spread of its sound (Q3−Q1, dB)'
});

// ── measuring a recording ───────────────────────────────────────────────
// Decoded a piece at a time, each piece being the file's own header in front
// of a byte range of its data — see energy_run.js, which supplies `io`.

// Frames per decoded piece: 1500 × 20 ms = 30 s.
const FRAMES_PER_PIECE = 1500;

// The noise floor is measured over at least this much audio around the
// stretch asked for. Over a short stretch that is all speech, the quietest
// frames are still speech, and measured there alone nothing would be found.
export const MIN_CONTEXT_SECONDS = 60;

// Frame levels of sample frames s0..s1 of each channel, decoded a piece at a
// time: [ Float32Array per channel ], one level per FRAME_SECONDS, the frames
// counted from s0 (the last one short if the stretch doesn't divide evenly).
// `on_samples(c, samples)`, if given, sees each piece's samples too — for
// what frame levels don't keep, such as the peak.
export async function measure_levels(io, { info, header, s0, s1, channels = info.channels, onprogress = null, on_samples = null }){
    const frame_len = Math.max(1, Math.round(info.sample_rate * FRAME_SECONDS));
    const piece = frame_len * FRAMES_PER_PIECE;
    const n_channels = Math.min(channels, info.channels);
    const levels = Array.from({ length: n_channels }, () => []);
    const pieces = Math.ceil((s1 - s0) / piece);
    for(let k = 0; k < pieces; k++){
        onprogress?.({ done: k, total: pieces });
        const a = s0 + k * piece;
        const b = Math.min(s1, a + piece);
        const bytes = await io.read(info.dataOffset + a * info.blockSize, info.dataOffset + b * info.blockSize - 1);
        const whole = new Uint8Array(header.byteLength + bytes.byteLength);
        whole.set(new Uint8Array(header), 0);
        whole.set(new Uint8Array(bytes), header.byteLength);
        const decoded = await io.decode(whole.buffer);
        for(let c = 0; c < n_channels; c++){
            const data = decoded[Math.min(c, decoded.length - 1)];
            // A decoder may hand back a sample or two more or fewer than asked
            // for; measure what this piece should hold, not what came back.
            const want = b - a;
            const samples = data.length > want ? data.subarray(0, want) : data;
            levels[c].push(frame_levels(samples, frame_len));
            on_samples?.(c, samples);
        }
    }
    onprogress?.({ done: pieces, total: pieces });
    return levels.map( (parts) => {
        const all = new Float32Array(parts.reduce( (n, p) => n + p.length, 0 ));
        let o = 0;
        for(const p of parts){ all.set(p, o); o += p.length; }
        return all;
    } );
}

// The p-quantile of ascending `sorted`, interpolating between ranks — the
// usual definition (R's type 7, numpy's default). noise_floor, by contrast,
// takes the lower rank without interpolating.
export function quantile(sorted, p){
    if(sorted.length == 0) return null;
    const h = (sorted.length - 1) * p;
    const lo = Math.floor(h);
    const hi = Math.min(lo + 1, sorted.length - 1);
    return sorted[lo] + (h - lo) * (sorted[hi] - sorted[lo]);
}

// The stretch the noise floor is measured over for beg..end: widened to at
// least MIN_CONTEXT_SECONDS, evenly where the recording allows.
export function floor_context(beg, end, duration){
    const extra = Math.max(0, (MIN_CONTEXT_SECONDS - (end - beg)) / 2);
    let m_beg = Math.max(0, beg - extra);
    let m_end = Math.min(duration, end + extra);
    m_end = Math.min(duration, Math.max(m_end, m_beg + MIN_CONTEXT_SECONDS));
    m_beg = Math.max(0, Math.min(m_beg, m_end - MIN_CONTEXT_SECONDS));
    return { m_beg, m_end };
}

// The sound-level settings last used in this browser (the dialog remembers
// them), with the defaults for anything not set — including settings added
// since they were saved.
export const SETTINGS_KEY = 'energy_segments';
export function remembered_params(){
    try {
        const x = JSON.parse(localStorage.getItem(SETTINGS_KEY) || 'null');
        if(x && typeof x === 'object') return { ...DEFAULTS, ...x };
    }
    catch(e){}
    return { ...DEFAULTS };
}

// Statistics on beg..end seconds of each channel, in dBFS (1.0 = full scale):
//
//   duration      seconds measured
//   frames        whole FRAME_SECONDS frames — a short last one is left out of
//                 the frame statistics so it can't skew them; a stretch
//                 shorter than one frame is measured as one
//   rms_db        level over every sample: 10·log10(mean of squares)
//   peak_db       20·log10(largest |sample|)
//   min, q1, median, q3, max   of the frame levels
//   silent        frames at or below SILENCE_DB (digital silence)
//
// With `params` (the sound-level settings), also what a sound-level run would
// make of the selection — for calibrating those settings on real audio:
//
//   floor_db, threshold_db   the background and the start threshold, measured
//                            over the same widened context a run uses
//   sound_share, sound_spread   sound_measures of the selection's frames
//                            against that run's end threshold
//
// Levels bottom out at −100 dB, where frame_levels does.
export async function selection_stats(io, { info, header, beg, end, channels = info.channels, onprogress = null, params = null }){
    const sr = info.sample_rate;
    const total = Math.floor(info.dataSize / info.blockSize);
    const s0 = Math.max(0, Math.floor(beg * sr));
    const s1 = Math.min(total, Math.ceil(end * sr));
    if(s1 <= s0) throw new Error('the selection has no audio in it');
    const frame_len = Math.max(1, Math.round(sr * FRAME_SECONDS));
    const n_channels = Math.min(channels, info.channels);
    const acc = Array.from({ length: n_channels }, () => ({ sumsq: 0, n: 0, peak: 0 }));
    const levels = await measure_levels(io, { info, header, s0, s1, channels, onprogress, on_samples: (c, x) => {
        const a = acc[c];
        for(let i = 0; i < x.length; i++){
            const v = x[i];
            a.sumsq += v * v;
            const m = v < 0 ? -v : v;
            if(m > a.peak) a.peak = m;
        }
        a.n += x.length;
    } });
    const whole = Math.floor((s1 - s0) / frame_len);
    const db = (x) => Math.max(-100, x);
    // The run's view: the floor over the widened context, read again for it.
    let context = null;
    if(params){
        const { m_beg, m_end } = floor_context(beg, end, info.duration);
        context = await measure_levels(io, { info, header, channels,
            s0: Math.max(0, Math.floor(m_beg * sr)), s1: Math.min(total, Math.ceil(m_end * sr)) });
    }
    return levels.map( (lv, c) => {
        const use = whole > 0 ? lv.subarray(0, whole) : lv;
        let run = {};
        if(context){
            const floor = noise_floor(context[c]);
            const on = floor + params.margin_db;
            const m = sound_measures(use, on - HYSTERESIS_DB);
            run = { floor_db: floor, threshold_db: on, sound_share: m.share, sound_spread: m.spread };
        }
        const sorted = Array.from(use).sort( (a, b) => a - b );
        const a = acc[c];
        return {
            duration: (s1 - s0) / sr,
            frames: use.length,
            rms_db: db(10 * Math.log10(a.sumsq / Math.max(1, a.n) + 1e-10)),
            peak_db: db(20 * Math.log10(a.peak + 1e-10)),
            min: sorted[0],
            q1: quantile(sorted, 0.25),
            median: quantile(sorted, 0.5),
            q3: quantile(sorted, 0.75),
            max: sorted[sorted.length - 1],
            silent: sorted.filter( (x) => x <= SILENCE_DB ).length,
            ...run
        };
    } );
}

// `io.read(b, e)` → ArrayBuffer of bytes b..e inclusive.
// `io.decode(buffer)` → array of Float32Array, one per channel.
// `info` is ParseB's reading of the header and `header` its bytes.
// `span` is { beg, end } in seconds (end may be Infinity).
// Returns per channel { floor, threshold, segments }.
export async function segment_audio(io, { info, header, span = null, params, channels = info.channels, onprogress = null }){
    const sr = info.sample_rate;
    const frame_len = Math.max(1, Math.round(sr * FRAME_SECONDS));
    const frame_seconds = frame_len / sr;
    const total = Math.floor(info.dataSize / info.blockSize);

    const beg = Math.max(0, span?.beg ?? 0);
    const end = Math.min(info.duration, span?.end ?? Infinity);
    if(end <= beg) return Array.from({ length: channels }, () => ({ floor: null, threshold: null, segments: [] }));
    const { m_beg, m_end } = floor_context(beg, end, info.duration);
    const s0 = Math.floor(m_beg * sr);
    const s1 = Math.min(total, Math.ceil(m_end * sr));

    const levels = await measure_levels(io, { info, header, s0, s1, channels, onprogress });
    return levels.map( (all) => {
        const r = segments_from_levels(all, { frame_seconds, offset: s0 / sr, duration: s1 / sr, params });
        // Only what falls in the stretch asked for, cut at its edges.
        r.segments = r.segments
            .filter( (x) => x.end > beg && x.beg < end )
            .map( (x) => ({ beg: Math.max(x.beg, round3(beg)), end: Math.min(x.end, round3(end)) }) )
            .filter( (x) => x.end > x.beg );
        return r;
    } );
}

// What a sound-level preview is called: its settings, so two runs can be
// told apart at a glance.
export function energy_label(params, span = null){
    const p = params || {};
    const parts = [ `margin ${p.margin_db} dB`, `pause ${p.min_silence} s`, `min ${p.min_segment} s` ];
    if(p.padding) parts.push(`pad ${p.padding} s`);
    parts.push(p.max_segment ? `max ${p.max_segment} s` : 'no max');
    if(p.min_sound_pct) parts.push(`sound ≥${p.min_sound_pct}%`);
    if(p.max_sound_spread != null) parts.push(`spread ≤${p.max_sound_spread} dB`);
    const where = span && (span.beg > 0 || span.end !== Infinity)
        ? ` · ${span.beg}–${span.end === Infinity ? 'end' : span.end} s` : '';
    return `Sound level · ${parts.join(', ')}${where}`;
}
