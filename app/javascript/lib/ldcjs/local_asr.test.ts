import { beforeEach, describe, expect, test, vi } from "vitest";
import {
  chunks_to_segments, run_local_asr, local_asr_available, webgpu_available,
  asr_model, asr_model_base
} from "./local_asr";

// The mapping from the library's chunks to this app's segments is the part
// worth testing: a wrong answer here puts text at the wrong time in the
// annotation log, which looks like a transcription mistake rather than a bug.
//
// The Worker and the decoder are injected. jsdom has neither a Worker nor an
// AudioContext, which is also what local_asr_available() reports.

function chunk(beg: number | null, end: number | null, text: string) {
  return { timestamp: [ beg, end ], text };
}

// A Worker stand-in: records what it was sent, and lets a test drive the
// replies in whatever order it wants to exercise.
function fake_worker() {
  const sent: any[] = [];
  const w: any = {
    sent,
    terminated: false,
    postMessage: (m: any) => sent.push(m),
    terminate: () => { w.terminated = true; },
    onmessage: null,
    onerror: null,
    reply: (m: any) => w.onmessage?.({ data: m }),
    fail: (m: any) => w.onerror?.(m)
  };
  return w;
}

const decode_to = (duration: number) => async () =>
  ({ samples: new Float32Array(16000 * duration), duration });

describe("chunks_to_segments", () => {
  test("a chunk becomes a segment with times, text and the run's labels", () => {
    const segs = chunks_to_segments([ chunk(0, 2.5, " hello there ") ],
                                    { duration: 10, channel: "ch_1", speaker: "2" });
    expect(segs).toEqual([
      { beg: 0, end: 2.5, text: "hello there", speaker: "2", channel: "ch_1" }
    ]);
  });

  test("a null end — which the last chunk of a real run often has — becomes the end of the audio", () => {
    const segs = chunks_to_segments([ chunk(8, null, "trailing words") ], { duration: 11.25 });
    expect(segs).toEqual([
      { beg: 8, end: 11.25, text: "trailing words", speaker: "0", channel: "ch_0" }
    ]);
  });

  test("a null end with no known duration is dropped, not guessed", () => {
    expect(chunks_to_segments([ chunk(8, null, "trailing") ])).toEqual([]);
  });

  test("a null start is unusable, so the chunk goes", () => {
    expect(chunks_to_segments([ chunk(null, 3, "where?") ], { duration: 10 })).toEqual([]);
  });

  test("empty and whitespace-only text is dropped", () => {
    expect(chunks_to_segments([ chunk(0, 1, "   "), chunk(1, 2, "") ], { duration: 5 })).toEqual([]);
  });

  test("a zero-length or inverted segment is dropped, as the service path drops them", () => {
    const segs = chunks_to_segments([ chunk(3, 3, "nothing"), chunk(5, 4, "backwards") ],
                                    { duration: 10 });
    expect(segs).toEqual([]);
  });

  test("an end past the audio is clamped to it", () => {
    const segs = chunks_to_segments([ chunk(9, 12, "over the edge") ], { duration: 10 });
    expect(segs[0].end).toBe(10);
  });

  test("times are rounded the way the rest of the app rounds them", () => {
    const segs = chunks_to_segments([ chunk(0.12345678, 1.98765432, "x") ], { duration: 5 });
    expect(segs[0].beg).toBe(0.123457);
    expect(segs[0].end).toBe(1.987654);
  });

  test("no chunks at all is an empty run, not an error", () => {
    expect(chunks_to_segments([], { duration: 5 })).toEqual([]);
    expect(chunks_to_segments(null as any)).toEqual([]);
    expect(chunks_to_segments(undefined as any)).toEqual([]);
  });

  test("the good chunks of a mixed run survive", () => {
    const segs = chunks_to_segments([
      chunk(0, 1.5, "one"),
      chunk(null, 2, "dropped"),
      chunk(2, 2, ""),
      chunk(2.5, null, "last")
    ], { duration: 4 });
    expect(segs.map(s => s.text)).toEqual([ "one", "last" ]);
    expect(segs.map(s => s.end)).toEqual([ 1.5, 4 ]);
  });
});

describe("run_local_asr", () => {
  let worker: any;
  beforeEach(() => { worker = fake_worker(); });

  const run = (opts: any = {}) =>
    run_local_asr(new Blob([ new Uint8Array(32) ], { type: "audio/wav" }), {
      decode: decode_to(6),
      worker_factory: () => worker,
      ...opts
    });

  test("sends the decoded samples to the worker and resolves with segments", async () => {
    const p = run({ channel: "ch_0" });
    await vi.waitUntil(() => worker.sent.length > 0);

    const sent = worker.sent[0];
    expect(sent.type).toBe("run");
    expect(sent.samples.length).toBe(16000 * 6);
    expect(sent.model).toBeTruthy();

    worker.reply({ type: "done", chunks: [ chunk(0, 1, "hi"), chunk(1, null, "there") ] });
    await expect(p).resolves.toEqual([
      { beg: 0, end: 1, text: "hi", speaker: "0", channel: "ch_0" },
      { beg: 1, end: 6, text: "there", speaker: "0", channel: "ch_0" }
    ]);
  });

  test("the worker is terminated whether the run succeeds or fails", async () => {
    const p = run();
    await vi.waitUntil(() => worker.sent.length > 0);
    worker.reply({ type: "done", chunks: [] });
    await p;
    expect(worker.terminated).toBe(true);

    const w2 = fake_worker();
    const p2 = run({ worker_factory: () => w2 });
    await vi.waitUntil(() => w2.sent.length > 0);
    w2.reply({ type: "error", message: "model not found" });
    await expect(p2).rejects.toThrow("model not found");
    expect(w2.terminated).toBe(true);
  });

  test("progress is reported, decoding first", async () => {
    const seen: string[] = [];
    const p = run({ onprogress: (m: any) => seen.push(m.stage) });
    await vi.waitUntil(() => worker.sent.length > 0);
    worker.reply({ type: "progress", stage: "downloading", loaded: 1, total: 2 });
    worker.reply({ type: "progress", stage: "transcribing" });
    worker.reply({ type: "done", chunks: [] });
    await p;
    expect(seen).toEqual([ "decoding", "downloading", "transcribing" ]);
  });

  test("a worker that dies rejects rather than hanging for ever", async () => {
    const p = run();
    await vi.waitUntil(() => worker.sent.length > 0);
    worker.fail({ message: "failed to import" });
    await expect(p).rejects.toThrow("failed to import");
  });

  test("an abort signal cancels the run and takes the worker with it", async () => {
    const ac = new AbortController();
    const p = run({ signal: ac.signal });
    await vi.waitUntil(() => worker.sent.length > 0);
    ac.abort();
    await expect(p).rejects.toThrow("cancelled");
    expect(worker.terminated).toBe(true);
  });

  test("an already-aborted signal stops before a worker is made", async () => {
    const ac = new AbortController();
    ac.abort();
    const factory = vi.fn();
    await expect(run({ signal: ac.signal, worker_factory: factory })).rejects.toThrow("cancelled");
    expect(factory).not.toHaveBeenCalled();
  });

  test("audio it cannot read is refused with a sayable message", async () => {
    await expect(run_local_asr(42 as any, { worker_factory: () => worker }))
      .rejects.toThrow(/unusable audio/);
  });
});

describe("what the browser can do", () => {
  test("jsdom has no Worker and no AudioContext, so a run is not available here", () => {
    expect(local_asr_available()).toBe(false);
  });

  test("webgpu is reported, not assumed", () => {
    expect(typeof webgpu_available()).toBe("boolean");
  });
});

describe("configuration", () => {
  test("the model and its host come from meta tags, with a working default", () => {
    expect(asr_model()).toBe("onnx-community/whisper-base.en");
    expect(asr_model_base()).toBe("");

    document.head.insertAdjacentHTML("beforeend",
      '<meta name="asr-model" content="onnx-community/whisper-small.en">' +
      '<meta name="asr-model-base" content="https://example.test/models">');
    try {
      expect(asr_model()).toBe("onnx-community/whisper-small.en");
      expect(asr_model_base()).toBe("https://example.test/models");
    }
    finally {
      document.head.querySelectorAll('meta[name^="asr-model"]').forEach(el => el.remove());
    }
  });

  test("an empty tag falls back rather than naming an empty model", () => {
    document.head.insertAdjacentHTML("beforeend", '<meta name="asr-model" content="">');
    try { expect(asr_model()).toBe("onnx-community/whisper-base.en"); }
    finally { document.head.querySelectorAll('meta[name="asr-model"]').forEach(el => el.remove()); }
  });
});
