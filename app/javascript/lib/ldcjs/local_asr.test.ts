import { beforeEach, describe, expect, test, vi } from "vitest";
import {
  chunks_to_segments, run_local_asr, run_local_asr_for, audio_url_for,
  local_asr_available, webgpu_available, asr_model, asr_model_base, asr_dtype
} from "./local_asr";
import { register_local_file, forget_local_files } from "./local_audio";

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
    // The quantisation has to travel with the run: the library defaults
    // anything that is not wasm to fp32, which for whisper-base.en is 291 MB
    // of weights rather than 77 MB.
    expect(sent.dtype).toBe("q8");

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

  test("a worker that dies with no message — which is what a load failure gives — points at the console", async () => {
    const p = run();
    await vi.waitUntil(() => worker.sent.length > 0);
    worker.fail({ message: "" });
    await expect(p).rejects.toThrow(/failed to start.*Content-Security-Policy/s);
  });

  test("an async worker factory is awaited, as the real one is", async () => {
    const w = fake_worker();
    const p = run({ worker_factory: async () => w });
    await vi.waitUntil(() => w.sent.length > 0);
    w.reply({ type: "done", chunks: [ chunk(0, 1, "awaited") ] });
    await expect(p).resolves.toHaveLength(1);
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

describe("reading the audio", () => {
  test("a local_audio kit's blob: url is read from the File, never fetched", async () => {
    // fetch() of a blob: url is blocked by connect-src, which lists 'self',
    // wss:, https: and *.amazonaws.com. It surfaces as "TypeError: Failed to
    // fetch" with only a console violation to go on, so this path must not
    // reach fetch at all.
    const file = new File([ new Uint8Array(64) ], "a.wav", { type: "audio/wav" });
    const url = register_local_file(file);
    const worker = fake_worker();
    const fetch_spy = vi.fn();
    (globalThis as any).fetch = fetch_spy;

    const p = run_local_asr(url, { decode: decode_to(2), worker_factory: () => worker });
    await vi.waitUntil(() => worker.sent.length > 0);
    worker.reply({ type: "done", chunks: [ chunk(0, 1, "read locally") ] });

    await expect(p).resolves.toHaveLength(1);
    expect(fetch_spy).not.toHaveBeenCalled();
    forget_local_files();
  });

  test("a url that cannot be fetched says which url, and points at CORS", async () => {
    (globalThis as any).fetch = async () => { throw new TypeError("Failed to fetch"); };
    await expect(run_local_asr("https://elsewhere.test/a.wav", { worker_factory: () => fake_worker() }))
      .rejects.toThrow(/could not fetch the audio at https:\/\/elsewhere.test\/a.wav .*CORS/);
  });

  test("a url that answers with an error status reports the status", async () => {
    (globalThis as any).fetch = async () => ({ ok: false, status: 403 } as any);
    await expect(run_local_asr("https://elsewhere.test/a.wav", { worker_factory: () => fake_worker() }))
      .rejects.toThrow(/HTTP 403/);
  });
});

describe("audio_url_for", () => {
  const ldc = (urls: any) => ({ resources: { urls } });

  test("a local_audio kit's blob: url", () => {
    expect(audio_url_for("local://a.wav", ldc({ "local://a.wav": "blob:http://x/1" })))
      .toBe("blob:http://x/1");
  });

  test("an ordinary http(s) kit", () => {
    expect(audio_url_for("a.wav", ldc({ "a.wav": "https://example.test/a.wav" })))
      .toBe("https://example.test/a.wav");
  });

  test("an s3 source reaches here already signed, because helpers.js writes the signed url back", () => {
    expect(audio_url_for("s3://b/a.wav", ldc({ "s3://b/a.wav": "https://b.s3.amazonaws.com/a.wav?X=1" })))
      .toBe("https://b.s3.amazonaws.com/a.wav?X=1");
  });

  test("an s3 path that was never signed says so, instead of fetching a relative url", () => {
    expect(() => audio_url_for("k", ldc({ k: "s3://bucket/a.wav" })))
      .toThrow(/has not been signed/);
  });

  test("no url at all names the docid", () => {
    expect(() => audio_url_for("missing.wav", ldc({}))).toThrow(/no audio url for missing.wav/);
    expect(() => audio_url_for("missing.wav", {} as any)).toThrow(/no audio url/);
  });
});

describe("run_local_asr_for", () => {
  test("resolves the docid's audio and transcribes it", async () => {
    const worker = fake_worker();
    const ldc = { resources: { urls: { "a.wav:A": "blob:http://x/2" } } };
    const fetched: string[] = [];
    (globalThis as any).fetch = async (u: string) => {
      fetched.push(u);
      return { ok: true, arrayBuffer: async () => new ArrayBuffer(16) } as any;
    };

    const p = run_local_asr_for("a.wav:A", ldc, {
      channel: "ch_0",
      decode: decode_to(3),
      worker_factory: () => worker
    });
    await vi.waitUntil(() => worker.sent.length > 0);
    worker.reply({ type: "done", chunks: [ chunk(0, 1, "one channel") ] });

    await expect(p).resolves.toEqual([
      { beg: 0, end: 1, text: "one channel", speaker: "0", channel: "ch_0" }
    ]);
    expect(fetched).toEqual([ "blob:http://x/2" ]);
  });

  test("a docid with no audio rejects before any worker is made", async () => {
    const factory = vi.fn();
    await expect(run_local_asr_for("x", { resources: { urls: {} } }, { worker_factory: factory }))
      .rejects.toThrow(/no audio url/);
    expect(factory).not.toHaveBeenCalled();
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

  test("the quantisation is configurable, and defaults to the small one", () => {
    expect(asr_dtype()).toBe("q8");

    document.head.insertAdjacentHTML("beforeend", '<meta name="asr-dtype" content="fp16">');
    try { expect(asr_dtype()).toBe("fp16"); }
    finally { document.head.querySelectorAll('meta[name="asr-dtype"]').forEach(el => el.remove()); }
  });

  test("an empty tag falls back rather than naming an empty model", () => {
    document.head.insertAdjacentHTML("beforeend", '<meta name="asr-model" content="">');
    try { expect(asr_model()).toBe("onnx-community/whisper-base.en"); }
    finally { document.head.querySelectorAll('meta[name="asr-model"]').forEach(el => el.remove()); }
  });
});
