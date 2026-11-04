import { describe, expect, test } from "vitest";
import {
  DEFAULTS, FRAME_SECONDS, frame_levels, noise_floor, segments_from_levels,
  split_long, parse_params, segment_audio, energy_label, quantile, selection_stats, sound_measures, remembered_params, floor_context
} from "./energy_segments";

// Levels at 20 ms a frame: `quiet` everywhere, `loud` over the given seconds.
function levels(seconds: number, loud_spans: [number, number][], quiet = -60, loud = -30) {
  const n = Math.round(seconds / FRAME_SECONDS);
  const out = new Float32Array(n).fill(quiet);
  for (const [a, b] of loud_spans) {
    for (let f = Math.round(a / FRAME_SECONDS); f < Math.round(b / FRAME_SECONDS); f++) out[f] = loud;
  }
  return out;
}

const no_pad = { ...DEFAULTS, padding: 0, max_segment: null };

// Single loud frames every `every` seconds over [a, b): a click train.
function clicks(seconds: number, a: number, b: number, every: number, quiet = -60, loud = -20) {
  const l = levels(seconds, [], quiet);
  for (let t = a; t < b; t += every) l[Math.round(t / FRAME_SECONDS)] = loud;
  return l;
}

describe("frame_levels", () => {
  test("is the RMS level in dB", () => {
    const x = new Float32Array(400).fill(0.1);
    const l = frame_levels(x, 100);
    expect(l.length).toBe(4);
    expect(l[0]).toBeCloseTo(-20, 3);
  });

  test("a short last frame is measured over what it has", () => {
    expect(frame_levels(new Float32Array(150).fill(0.1), 100)[1]).toBeCloseTo(-20, 3);
  });
});

describe("noise_floor", () => {
  test("is a low percentile of the levels, not the minimum", () => {
    const l = new Float32Array(100).fill(-50);
    l[0] = -80;
    expect(noise_floor(l)).toBe(-50);
  });

  // Digital silence would put the floor at the bottom of the scale, and then
  // every bit of hiss counts as sound.
  test("ignores digital silence", () => {
    const l = new Float32Array(100).fill(-100);
    for (let i = 0; i < 40; i++) l[i] = -55;
    expect(noise_floor(l)).toBe(-55);
  });
});

describe("segments_from_levels", () => {
  test("finds the loud stretches, threshold a margin above the floor", () => {
    const r = segments_from_levels(levels(10, [[1, 2], [5, 6.5]]), { params: no_pad });
    expect(r.floor).toBe(-60);
    expect(r.threshold).toBe(-50);
    expect(r.segments).toEqual([{ beg: 1, end: 2 }, { beg: 5, end: 6.5 }]);
  });

  test("pads each edge, clipped to the stretch measured", () => {
    const r = segments_from_levels(levels(10, [[0, 1], [5, 6]]), { params: { ...no_pad, padding: 0.1 } });
    expect(r.segments).toEqual([{ beg: 0, end: 1.1 }, { beg: 4.9, end: 6.1 }]);
  });

  test("a pause shorter than min_silence doesn't end a segment", () => {
    const r = segments_from_levels(levels(10, [[1, 2], [2.2, 3]]), { params: no_pad });
    expect(r.segments).toEqual([{ beg: 1, end: 3 }]);
  });

  test("a longer pause does", () => {
    const r = segments_from_levels(levels(10, [[1, 2], [2.5, 3]]), { params: no_pad });
    expect(r.segments).toEqual([{ beg: 1, end: 2 }, { beg: 2.5, end: 3 }]);
  });

  test("sound shorter than min_segment is dropped", () => {
    const r = segments_from_levels(levels(10, [[1, 1.1], [5, 6]]), { params: no_pad });
    expect(r.segments).toEqual([{ beg: 5, end: 6 }]);
  });

  test("the margin decides what counts as sound", () => {
    const l = levels(10, [[1, 2]], -60, -52);
    expect(segments_from_levels(l, { params: no_pad }).segments).toEqual([]);
    expect(segments_from_levels(l, { params: { ...no_pad, margin_db: 6 } }).segments).toEqual([{ beg: 1, end: 2 }]);
  });

  test("padding that would overlap a neighbour meets it in the middle", () => {
    const r = segments_from_levels(levels(10, [[1, 2], [2.4, 3]]), { params: { ...no_pad, padding: 0.3 } });
    expect(r.segments).toEqual([{ beg: 0.7, end: 2.2 }, { beg: 2.2, end: 3.3 }]);
  });

  test("times are from the start of the recording when measuring a stretch", () => {
    const r = segments_from_levels(levels(4, [[1, 2]]), { offset: 30, duration: 34, params: no_pad });
    expect(r.segments).toEqual([{ beg: 31, end: 32 }]);
  });

  test("a long segment is split at its quietest point", () => {
    const l = levels(30, [[1, 25]]);
    for (let f = Math.round(9 / FRAME_SECONDS); f < Math.round(9.1 / FRAME_SECONDS); f++) l[f] = -45;
    const r = segments_from_levels(l, { params: { ...no_pad, max_segment: 15 } });
    expect(r.segments[0]).toEqual({ beg: 1, end: 9 });
    expect(r.segments.every((s) => s.end - s.beg <= 15)).toBe(true);
    expect(r.segments[r.segments.length - 1].end).toBe(25);
  });
});

describe("split_long", () => {
  test("leaves a run within the limit alone", () => {
    expect(split_long([0, 10], new Float32Array(10), 10, 2)).toEqual([[0, 10]]);
  });

  test("never leaves a piece shorter than the minimum", () => {
    const l = new Float32Array(100).fill(-30);
    l[1] = -60; // quietest, but too close to the edge to cut at
    const parts = split_long([0, 100], l, 60, 10);
    expect(parts.every(([s, e]) => e - s >= 10)).toBe(true);
    expect(parts[0][0]).toBe(0);
    expect(parts[parts.length - 1][1]).toBe(100);
  });
});

describe("parse_params", () => {
  const fields = (o: Record<string, string> = {}) => ({
    margin_db: "10", min_silence: "0.3", min_segment: "0.3", padding: "0.1", max_segment: "15", ...o
  });

  test("numbers through", () => {
    expect(parse_params(fields()).params).toEqual({ ...DEFAULTS });
  });

  test("the click settings: blank share is the default, blank spread is off", () => {
    expect(parse_params(fields({ min_sound_pct: "", max_sound_spread: "" })).params)
      .toMatchObject({ min_sound_pct: 50, max_sound_spread: null });
    expect(parse_params(fields({ min_sound_pct: "30", max_sound_spread: "12" })).params)
      .toMatchObject({ min_sound_pct: 30, max_sound_spread: 12 });
    expect(parse_params(fields({ min_sound_pct: "120" })).error).toMatch(/percentage/);
    expect(parse_params(fields({ max_sound_spread: "0" })).error).toMatch(/spread limit/);
  });

  test("a blank maximum means no limit; other blanks the default", () => {
    expect(parse_params(fields({ max_segment: "", padding: "" })).params).toEqual({ ...DEFAULTS, max_segment: null });
  });

  test("refuses what can't work", () => {
    expect(parse_params(fields({ margin_db: "x" })).error).toMatch(/number/);
    expect(parse_params(fields({ margin_db: "0" })).error).toMatch(/margin/);
    expect(parse_params(fields({ padding: "-1" })).error).toMatch(/negative/);
    expect(parse_params(fields({ max_segment: "0.5" })).error).toMatch(/twice/);
  });
});

describe("segment_audio", () => {
  // A 1 kHz, 2-channel, 16-bit file of 100 s: channel 0 loud over 10–12 s,
  // channel 1 over 70–71 s. The fake decoder knows where each piece starts
  // from the byte range it was read from.
  const sr = 1000, block = 4, offset = 44, seconds = 100;
  const info = { sample_rate: sr, channels: 2, blockSize: block, dataOffset: offset,
                 dataSize: sr * seconds * block, duration: seconds };
  const header = new ArrayBuffer(offset);
  const amp = (c: number, t: number) =>
    (c == 0 && t >= 10 && t < 12) || (c == 1 && t >= 70 && t < 71) ? 0.3 : 0.003;

  function io() {
    const reads: [number, number][] = [];
    let last: [number, number] = [0, 0];
    return {
      reads,
      read: async (b: number, e: number) => { reads.push([b, e]); last = [b, e]; return new ArrayBuffer(e - b + 1); },
      decode: async (buf: ArrayBuffer) => {
        expect(buf.byteLength - offset).toBe(last[1] - last[0] + 1);
        const first = (last[0] - offset) / block;
        const n = (buf.byteLength - offset) / block;
        return [0, 1].map((c) => Float32Array.from({ length: n }, (_, i) => amp(c, (first + i) / sr)));
      }
    };
  }

  test("measures in pieces, each with the header in front, and segments each channel", async () => {
    const x = io();
    const r = await segment_audio(x, { info, header, params: no_pad });
    expect(x.reads.length).toBe(4); // 100 s in 30 s pieces
    expect(x.reads[0][0]).toBe(offset);
    expect(x.reads[3][1]).toBe(offset + sr * seconds * block - 1);
    expect(r[0].segments).toEqual([{ beg: 10, end: 12 }]);
    expect(r[1].segments).toEqual([{ beg: 70, end: 71 }]);
  });

  test("reads the stretch asked for, widened to a minute for the noise floor", async () => {
    const x = io();
    const r = await segment_audio(x, { info, header, span: { beg: 60, end: 80 }, params: no_pad });
    // 20 s asked for, so 20 s either side: 40–100 s, two pieces.
    expect(x.reads[0][0]).toBe(offset + 40 * sr * block);
    expect(x.reads[x.reads.length - 1][1]).toBe(offset + 100 * sr * block - 1);
    expect(r[0].segments).toEqual([]);
    expect(r[1].segments).toEqual([{ beg: 70, end: 71 }]);
  });

  // The case that made the context necessary: a stretch that is all sound.
  test("a short stretch inside speech still finds it, against the background around it", async () => {
    const r = await segment_audio(io(), { info, header, span: { beg: 10.5, end: 11.5 }, params: no_pad });
    expect(r[0].segments).toEqual([{ beg: 10.5, end: 11.5 }]);
    expect(r[0].floor).toBeLessThan(-40);
  });

  test("segments are cut at the edges of the stretch", async () => {
    const r = await segment_audio(io(), { info, header, span: { beg: 11, end: 50 }, params: no_pad });
    expect(r[0].segments).toEqual([{ beg: 11, end: 12 }]);
  });

  test("near the start, the minute of context comes from after", async () => {
    const x = io();
    await segment_audio(x, { info, header, span: { beg: 0, end: 10 }, params: no_pad });
    expect(x.reads[0][0]).toBe(offset);
    expect(x.reads[x.reads.length - 1][1]).toBe(offset + 60 * sr * block - 1);
  });

  test("an end past the recording stops at its end", async () => {
    const x = io();
    await segment_audio(x, { info, header, span: { beg: 90, end: Infinity }, params: no_pad });
    expect(x.reads[x.reads.length - 1][1]).toBe(offset + sr * seconds * block - 1);
  });

  test("measures only as many channels as asked for", async () => {
    const r = await segment_audio(io(), { info, header, channels: 1, params: no_pad });
    expect(r.length).toBe(1);
  });

  test("reports progress by piece", async () => {
    const seen: any[] = [];
    await segment_audio(io(), { info, header, params: no_pad, onprogress: (m: any) => seen.push(m) });
    expect(seen[0]).toEqual({ done: 0, total: 4 });
    expect(seen[seen.length - 1]).toEqual({ done: 4, total: 4 });
  });
});

describe("energy_label", () => {
  test("a sound-level preview is named by its settings", () => {
    const p = { margin_db: 8, min_silence: 0.3, min_segment: 0.3, padding: 0.1, max_segment: 15 };
    expect(energy_label(p)).toBe("Sound level · margin 8 dB, pause 0.3 s, min 0.3 s, pad 0.1 s, max 15 s");
    expect(energy_label({ ...p, max_segment: null, padding: 0 }, { beg: 30, end: Infinity }))
      .toBe("Sound level · margin 8 dB, pause 0.3 s, min 0.3 s, no max · 30–end s");
  });
});

describe("quantile", () => {
  test("interpolates between ranks", () => {
    const x = [1, 2, 3, 4];
    expect(quantile(x, 0)).toBe(1);
    expect(quantile(x, 0.25)).toBe(1.75);
    expect(quantile(x, 0.5)).toBe(2.5);
    expect(quantile(x, 1)).toBe(4);
    expect(quantile([7], 0.75)).toBe(7);
    expect(quantile([], 0.5)).toBeNull();
  });
});

describe("selection_stats", () => {
  // 1 kHz, 2 channels: the first 0.5 for a second, then 0.05; the second
  // silent. 20 ms frames are 20 samples.
  const sr = 1000, block = 4, offset = 44, seconds = 10;
  const info = { sample_rate: sr, channels: 2, blockSize: block, dataOffset: offset, dataSize: sr * seconds * block, duration: seconds };
  const header = new ArrayBuffer(offset);
  const value = (c: number, t: number) => c == 0 ? (t < 1 ? 0.5 : 0.05) : 0;
  function io() {
    let last = [0, 0];
    return {
      read: async (b: number, e: number) => { last = [b, e]; return new ArrayBuffer(e - b + 1); },
      decode: async (buf: ArrayBuffer) => {
        const first = (last[0] - offset) / block;
        const n = (buf.byteLength - offset) / block;
        return [0, 1].map((c) => Float32Array.from({ length: n }, (_, i) => value(c, (first + i) / sr)));
      }
    };
  }
  const db = (x: number) => 10 * Math.log10(x);

  test("level, peak and the quartiles of the frame levels, per channel", async () => {
    const [a, b] = await selection_stats(io(), { info, header, beg: 0, end: 2 });
    expect(a.duration).toBe(2);
    expect(a.frames).toBe(100);
    expect(a.peak_db).toBeCloseTo(20 * Math.log10(0.5), 3);
    expect(a.rms_db).toBeCloseTo(db((0.25 + 0.0025) / 2), 3);
    // fifty frames at each level: the median falls between them
    expect(a.min).toBeCloseTo(db(0.0025), 3);
    expect(a.q1).toBeCloseTo(db(0.0025), 3);
    expect(a.median).toBeCloseTo((db(0.0025) + db(0.25)) / 2, 3);
    expect(a.q3).toBeCloseTo(db(0.25), 3);
    expect(a.max).toBeCloseTo(db(0.25), 3);
    expect(a.silent).toBe(0);
    expect(b).toMatchObject({ frames: 100, silent: 100, peak_db: -100, rms_db: -100, median: -100 });
  });

  test("a short last frame is left out of the frame statistics", async () => {
    const [a] = await selection_stats(io(), { info, header, beg: 0, end: 0.05 });
    expect(a.duration).toBe(0.05);
    expect(a.frames).toBe(2);
  });

  test("a selection shorter than a frame is one frame", async () => {
    const [a] = await selection_stats(io(), { info, header, beg: 0.5, end: 0.51 });
    expect(a.frames).toBe(1);
    expect(a.median).toBeCloseTo(db(0.25), 3);
  });

  // With the settings, what a run would see: the floor over the context
  // (here all 10 s: 50 frames at −6 dB, 450 at −26), the threshold a margin
  // above it, and how much of the selection clears it.
  test("with the sound-level settings, the floor, threshold and sound share a run would see", async () => {
    const [a, b] = await selection_stats(io(), { info, header, beg: 0, end: 2, params: { ...DEFAULTS, margin_db: 10 } });
    expect(a.floor_db).toBeCloseTo(db(0.0025), 3);
    expect(a.threshold_db).toBeCloseTo(db(0.0025) + 10, 3);
    expect(a.sound_share).toBe(0.5);   // the loud first second
    expect(a.sound_spread).toBeCloseTo(0, 6);
    expect(b.sound_share).toBe(0);
  });

  test("without them, none of that", async () => {
    const [a] = await selection_stats(io(), { info, header, beg: 0, end: 2 });
    expect(a.floor_db).toBeUndefined();
  });

  test("an empty selection is an error", async () => {
    await expect(selection_stats(io(), { info, header, beg: 3, end: 3 })).rejects.toThrow(/no audio/);
  });
});

describe("sound_measures", () => {
  test("the share of frames at or above the end threshold, and their spread", () => {
    const m = sound_measures([-60, -60, -30, -20, -10, -40], -45);
    expect(m.share).toBeCloseTo(4 / 6, 6);
    expect(m.spread).toBeCloseTo(-17.5 - -32.5, 6);
  });
  test("fewer than four sound frames have no spread to speak of", () => {
    expect(sound_measures([-20, -60, -10], -45)).toEqual({ share: 2 / 3, spread: 0 });
    expect(sound_measures([], -45)).toEqual({ share: 0, spread: 0 });
  });
});

describe("rejecting clicks and impulses", () => {
  test("a click train — loud frames joined across short gaps — is mostly background, and rejected", () => {
    // a click every 100 ms for 2 s: one sound frame in five
    const r = segments_from_levels(clicks(10, 3, 5, 0.1), { params: no_pad });
    expect(r.segments).toEqual([]);
    expect(r.rejected).toEqual({ not_enough_sound: 1, too_spread: 0 });
  });

  test("the share can be lowered to keep them", () => {
    const r = segments_from_levels(clicks(10, 3, 5, 0.1), { params: { ...no_pad, min_sound_pct: 10 } });
    expect(r.segments.length).toBe(1);
  });

  test("speech-like sound with a short pause in it is kept", () => {
    // 1.8 s of sound with a 0.2 s pause: 90 % sound
    const r = segments_from_levels(levels(10, [[1, 2], [2.2, 3]]), { params: no_pad });
    expect(r.segments).toEqual([{ beg: 1, end: 3 }]);
    expect(r.rejected.not_enough_sound).toBe(0);
  });

  test("a knock — loud, then decaying steadily — is rejected only when a spread limit is set", () => {
    const l = levels(10, [], -60);
    // 0.5 s from −15 dB falling 1 dB a frame
    for (let f = 0; f < 25; f++) l[Math.round(4 / FRAME_SECONDS) + f] = -15 - f;
    expect(segments_from_levels(l, { params: no_pad }).segments.length).toBe(1);
    const r = segments_from_levels(l, { params: { ...no_pad, max_sound_spread: 8 } });
    expect(r.segments).toEqual([]);
    expect(r.rejected).toEqual({ not_enough_sound: 0, too_spread: 1 });
  });

  test("steady sound passes a spread limit", () => {
    const r = segments_from_levels(levels(10, [[1, 2]]), { params: { ...no_pad, max_sound_spread: 8 } });
    expect(r.segments).toEqual([{ beg: 1, end: 2 }]);
  });
});

describe("remembered settings", () => {
  test("ones saved before a setting existed get its default", () => {
    localStorage.setItem("energy_segments", JSON.stringify({ margin_db: 12, min_silence: 0.3, min_segment: 0.3, padding: 0.1, max_segment: 15 }));
    expect(remembered_params()).toMatchObject({ margin_db: 12, min_sound_pct: 50, max_sound_spread: null });
    localStorage.removeItem("energy_segments");
    expect(remembered_params()).toEqual({ ...DEFAULTS });
  });
});

describe("floor_context", () => {
  test("at least a minute, evenly where the recording allows", () => {
    expect(floor_context(100, 120, 600)).toEqual({ m_beg: 80, m_end: 140 });
    expect(floor_context(0, 10, 600)).toEqual({ m_beg: 0, m_end: 60 });
    expect(floor_context(590, 600, 600)).toEqual({ m_beg: 540, m_end: 600 });
    expect(floor_context(0, 5, 20)).toEqual({ m_beg: 0, m_end: 20 });
  });
});

