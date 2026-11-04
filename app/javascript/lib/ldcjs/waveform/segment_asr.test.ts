import { describe, expect, test } from "vitest";
import {
  is_empty_segment, rows_to_transcribe, source_for, segment_bytes, transcribe_rows, summarize, download_tracker, rows_ahead, suggestion_key
} from "./segment_asr";
import { open_local_asr_session, clean_segment_text } from "../local_asr";

const row = (iid: number, beg: number, end: number, text = "", extra: any = {}) =>
  ({ iid, beg, end, text, docid: "d", ...extra });

describe("which segments", () => {
  test("empty means no text but times, and the annotator's own", () => {
    expect(is_empty_segment(row(1, 0, 1))).toBe(true);
    expect(is_empty_segment(row(1, 0, 1, "  "))).toBe(true);
    expect(is_empty_segment(row(1, 0, 1, "hi"))).toBe(false);
    expect(is_empty_segment(row(1, 0, 1, "", { readonly: true }))).toBe(false);
    expect(is_empty_segment(row(1, 0, 1, "", { virtual: true }))).toBe(false);
    expect(is_empty_segment(row(1, null as any, 1))).toBe(false);
    expect(is_empty_segment(row(1, 1, 1))).toBe(false);
  });

  test("a batch takes the empty ones fitting inside the stretch, in time order", () => {
    const rows = [row(5, 6, 7), row(1, 0, 1), row(2, 2, 3, "done"), row(3, 4.5, 5.5), row(4, 9, 11)];
    expect(rows_to_transcribe(rows).map((r) => r.iid)).toEqual([1, 3, 5, 4]);
    expect(rows_to_transcribe(rows, { beg: 4, end: 10 }).map((r) => r.iid)).toEqual([3, 5]);
  });
});

describe("source_for", () => {
  test("one file with a docid per channel", () => {
    expect(source_for("f:B", ["f:A", "f:B"], ["f"])).toEqual({ source_uid: "f", channel: 1 });
  });
  test("a file per channel", () => {
    expect(source_for("b", ["a", "b"], ["a.wav", "b.wav"])).toEqual({ source_uid: "b.wav", channel: 0 });
  });
  test("a docid not in the list is the first channel", () => {
    expect(source_for("x", ["f"], ["f"])).toEqual({ source_uid: "f", channel: 0 });
  });
});

describe("segment_bytes", () => {
  // 1 kHz, 2 bytes a frame, data at 44.
  const info = { sample_rate: 1000, blockSize: 2, dataOffset: 44, dataSize: 2000 * 2 };
  const header = new Uint8Array(44).fill(7).buffer;

  test("the header, then exactly the segment's frames", async () => {
    const reads: number[][] = [];
    const read = async (b: number, e: number) => { reads.push([b, e]); return new Uint8Array(e - b + 1).fill(1).buffer; };
    const buf = new Uint8Array(await segment_bytes({ read, info, header }, 0.5, 0.75));
    expect(reads).toEqual([[44 + 500 * 2, 44 + 750 * 2 - 1]]);
    expect(buf.length).toBe(44 + 250 * 2);
    expect(buf[0]).toBe(7);
    expect(buf[44]).toBe(1);
  });

  test("stops at the end of the data", async () => {
    const reads: number[][] = [];
    const read = async (b: number, e: number) => { reads.push([b, e]); return new ArrayBuffer(e - b + 1); };
    await segment_bytes({ read, info, header }, 1.9, 5);
    expect(reads[0][1]).toBe(44 + 2000 * 2 - 1);
  });
});

describe("transcribe_rows", () => {
  const samples_for = async () => new Float32Array(16);
  const session = (answers: Record<number, string | Error>) => {
    let n = 0;
    return { transcribe: async () => { const a = answers[n++]; if (a instanceof Error) throw a; return a ?? ""; } };
  };

  test("writes each one's text, and counts what happened", async () => {
    const written: any[] = [];
    const r = await transcribe_rows([row(1, 0, 1), row(2, 1, 2), row(3, 2, 3)], {
      samples_for,
      session: session({ 0: "hello", 1: "", 2: "there" }),
      write: async (row: any, text: string) => { written.push([row.iid, text]); return true; }
    });
    expect(written).toEqual([[1, "hello"], [3, "there"]]);
    expect(r).toMatchObject({ written: 2, nothing_heard: 1, skipped: 0, failed: [], cancelled: false });
  });

  // write() is where "still empty?" is asked, at the moment the text arrives.
  test("a segment typed into meanwhile is skipped, not overwritten", async () => {
    const r = await transcribe_rows([row(1, 0, 1)], {
      samples_for, session: session({ 0: "hello" }), write: async () => false
    });
    expect(r).toMatchObject({ written: 0, skipped: 1 });
  });

  test("one failure is reported and the run goes on", async () => {
    const written: number[] = [];
    const r = await transcribe_rows([row(1, 0, 1), row(2, 1, 2)], {
      samples_for,
      session: session({ 0: new Error("bad audio"), 1: "ok" }),
      write: async (row: any) => { written.push(row.iid); return true; }
    });
    expect(written).toEqual([2]);
    expect(r.failed.map((f) => [f.row.iid, f.message])).toEqual([[1, "bad audio"]]);
  });

  test("cancelling stops before the next segment and keeps what was written", async () => {
    const ac = new AbortController();
    const written: number[] = [];
    const r = await transcribe_rows([row(1, 0, 1), row(2, 1, 2), row(3, 2, 3)], {
      samples_for, session: session({ 0: "a", 1: "b", 2: "c" }), signal: ac.signal,
      write: async (row: any) => { written.push(row.iid); if (row.iid == 1) ac.abort(); return true; }
    });
    expect(written).toEqual([1]);
    expect(r.cancelled).toBe(true);
  });

  test("reports progress per segment", async () => {
    const seen: number[][] = [];
    await transcribe_rows([row(1, 0, 1), row(2, 1, 2)], {
      samples_for, session: session({}), write: async () => true,
      onprogress: (d: number, t: number) => seen.push([d, t])
    });
    expect(seen).toEqual([[0, 2], [1, 2], [2, 2]]);
  });

  test("summarize says it in one line", () => {
    expect(summarize({ written: 3, nothing_heard: 1, skipped: 0, failed: [], cancelled: false }))
      .toBe("3 segments transcribed, 1 with no speech recognised.");
    expect(summarize({ written: 1, nothing_heard: 0, skipped: 1, failed: [{ row: {}, message: "x" }], cancelled: true }))
      .toBe("Stopped: 1 segment transcribed, 1 skipped because text was typed meanwhile, 1 failed (x).");
  });
});

describe("clean_segment_text", () => {
  test("drops what Whisper says about non-speech", () => {
    expect(clean_segment_text(" [BLANK_AUDIO] ")).toBe("");
    expect(clean_segment_text("(upbeat music)")).toBe("");
    expect(clean_segment_text("Hello [Music] there.")).toBe("Hello there.");
  });
  test("leaves words alone", () => {
    expect(clean_segment_text("  Hello, world.  ")).toBe("Hello, world.");
  });
});

describe("open_local_asr_session", () => {
  function fake_worker() {
    const w: any = {
      sent: [] as any[], terminated: false, onmessage: null, onerror: null,
      postMessage: (m: any) => w.sent.push(m),
      terminate: () => { w.terminated = true; },
      reply: (m: any) => w.onmessage?.({ data: m })
    };
    return w;
  }
  const tick = () => new Promise((r) => setTimeout(r, 0));

  test("one Worker for many segments, asked one at a time", async () => {
    const w = fake_worker();
    let made = 0;
    const s = await open_local_asr_session({ worker_factory: async () => { made++; return w; } });
    const a = s.transcribe(new Float32Array(4));
    const b = s.transcribe(new Float32Array(4));
    await tick();
    expect(w.sent.length).toBe(1); // the second waits for the first
    w.reply({ type: "done", text: " first [BLANK_AUDIO]" });
    expect(await a).toBe("first");
    await tick();
    expect(w.sent.length).toBe(2);
    w.reply({ type: "done", chunks: [{ text: "second" }] });
    expect(await b).toBe("second");
    expect(made).toBe(1);
    s.close();
    expect(w.terminated).toBe(true);
  });

  test("a failed request rejects alone; the next still runs", async () => {
    const w = fake_worker();
    const s = await open_local_asr_session({ worker_factory: async () => w });
    const a = s.transcribe(new Float32Array(4));
    await tick();
    w.reply({ type: "error", message: "transcribing: boom" });
    await expect(a).rejects.toThrow("boom");
    const b = s.transcribe(new Float32Array(4));
    await tick();
    w.reply({ type: "done", text: "fine" });
    expect(await b).toBe("fine");
  });

  // A terminated Worker never answers; without this a cancel would hang.
  test("closing ends the request in flight", async () => {
    const w = fake_worker();
    const s = await open_local_asr_session({ worker_factory: async () => w });
    const a = s.transcribe(new Float32Array(4));
    await tick();
    s.close();
    await expect(a).rejects.toThrow("cancelled");
    await expect(s.transcribe(new Float32Array(4))).rejects.toThrow("cancelled");
  });

  test("timestamps are asked for unless a request says otherwise", async () => {
    const w = fake_worker();
    const s = await open_local_asr_session({ worker_factory: async () => w });
    const a = s.transcribe(new Float32Array(4));
    await tick();
    w.reply({ type: "done", text: "x" });
    await a;
    const b = s.transcribe(new Float32Array(4), { timestamps: false });
    await tick();
    w.reply({ type: "done", text: "y" });
    await b;
    expect(w.sent.map((m: any) => m.timestamps)).toEqual([true, false]);
  });

  test("model progress is passed on", async () => {
    const w = fake_worker();
    const seen: any[] = [];
    const s = await open_local_asr_session({ worker_factory: async () => w, onprogress: (m: any) => seen.push(m) });
    const a = s.transcribe(new Float32Array(4));
    await tick();
    w.reply({ type: "progress", stage: "downloading", loaded: 5, total: 10 });
    w.reply({ type: "done", text: "x" });
    await a;
    expect(seen).toEqual([{ type: "progress", stage: "downloading", loaded: 5, total: 10 }]);
  });
});

describe("download_tracker", () => {
  test("totals every file, so the percentage only goes up", () => {
    const pct = download_tracker();
    expect(pct({ stage: "loading" })).toBeNull();
    expect(pct({ stage: "downloading", file: "config.json", loaded: 1, total: 1 })).toBe(100);
    expect(pct({ stage: "downloading", file: "encoder.onnx", loaded: 10, total: 99 })).toBe(11);
    expect(pct({ stage: "downloading", file: "decoder.onnx", loaded: 0, total: 100 })).toBe(6);
    expect(pct({ stage: "downloading", file: "encoder.onnx", loaded: 99, total: 99 })).toBe(50);
  });
});

describe("rows_ahead", () => {
  const rows = [row(1, 0, 1, "done"), row(2, 1, 2), row(3, 2, 3, "done"), row(4, 3, 4), row(5, 4, 5), row(6, 5, 6)];
  test("the first n empty segments from the start, the start included", () => {
    expect(rows_ahead(rows, 1, 2).map((r) => r.iid)).toEqual([2, 4]);
    expect(rows_ahead(rows, 4, 5).map((r) => r.iid)).toEqual([5, 6]);
  });
  test("no start means the top", () => {
    expect(rows_ahead(rows, null, 1).map((r) => r.iid)).toEqual([2]);
  });
  test("a suggestion is keyed by the segment and its times", () => {
    expect(suggestion_key(row(4, 3, 4.5))).toBe("4@3-4.5");
    expect(suggestion_key(row(4, 3, 4.5))).not.toBe(suggestion_key(row(4, 3, 4.6)));
  });
});

