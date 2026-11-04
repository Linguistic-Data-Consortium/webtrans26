import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  register_resource, registered, unregister_all, rows_for, caches_used, cached_fetch,
  define_wasm_module, MODULE_CACHE
} from "./registry";
import { model_key, runtime_key, model_label, MODEL_CACHE } from "./speech";

const HF = "https://huggingface.co/onnx-community";

// Cache Storage in memory: open/has/match/put/keys/delete.
function memory_caches() {
  const all = new Map<string, Map<string, Response>>();
  const open = async (name: string) => {
    if (!all.has(name)) all.set(name, new Map());
    const m = all.get(name)!;
    return {
      match: async (u: any) => m.get(u.url ?? u)?.clone(),
      put: async (u: any, r: Response) => { m.set(u.url ?? u, r); },
      keys: async () => [...m.keys()].map((url) => ({ url })),
      delete: async (u: any) => m.delete(u.url ?? u)
    };
  };
  return { all, open, has: async (n: string) => all.has(n) };
}

describe("speech resources", () => {
  test("a model file's url names its model; anything else isn't one", () => {
    expect(model_key(`${HF}/whisper-base.en/resolve/main/onnx/encoder_model_quantized.onnx`)).toBe("onnx-community/whisper-base.en");
    expect(model_key("https://models.example.org/onnx-community/whisper-small/resolve/main/config.json")).toBe("onnx-community/whisper-small");
    expect(model_key("https://cdn.jsdelivr.net/npm/onnxruntime-web@1.31.0/dist/ort-wasm-simd-threaded.asyncify.wasm")).toBeNull();
  });

  test("the runtime is its wasm and mjs files", () => {
    expect(runtime_key("https://cdn.jsdelivr.net/npm/onnxruntime-web@1.31.0/dist/ort-wasm-simd-threaded.asyncify.wasm")).toBe("runtime");
    expect(runtime_key("https://x/ort-wasm-simd-threaded.asyncify.mjs")).toBe("runtime");
    expect(runtime_key(`${HF}/whisper-base.en/resolve/main/config.json`)).toBeNull();
  });

  test("models are named by what the dialog offers", () => {
    expect(model_label("onnx-community/whisper-tiny.en")).toBe("Whisper tiny (English)");
    expect(model_label("someone/else")).toBe("someone/else");
  });
});

describe("rows_for", () => {
  const family = {
    id: "fam", cache: "c1", label: (k: string) => `Model ${k}`,
    key: (url: string) => url.match(/\/m\/(\w+)\//)?.[1] ?? null,
    keys: () => ["b"], in_use: (k: string) => k == "b",
    download: async () => {}, can_download: (k: string) => k == "b"
  };
  const single = { id: "rt", cache: "c1", label: "Runtime", key: (url: string) => url.endsWith(".wasm") ? "rt" : null };
  const mod = { id: "vad", cache: "c2", label: "VAD", key: (url: string) => url.includes("vad") ? "vad" : null, keys: () => ["vad"], download: async () => {} };

  const entries = {
    c1: [
      { url: "https://h/m/a/x.onnx", size: 10 },
      { url: "https://h/m/a/y.json", size: 1 },
      { url: "https://h/r.wasm", size: 5 },
      { url: "https://h/leftover.bin", size: 7 }
    ],
    c2: []
  };

  test("a row per key: downloaded ones with their files and size", () => {
    const rows = rows_for([family, single, mod], entries);
    const a = rows.find((r) => r.id == "fam:a")!;
    expect([a.label, a.files.length, a.size, a.downloaded, a.in_use, a.can_download]).toEqual(["Model a", 2, 11, true, false, false]);
    expect(rows.find((r) => r.id == "rt:rt")).toMatchObject({ label: "Runtime", size: 5, downloaded: true, can_download: false });
  });

  // So they can be downloaded ahead.
  test("keys a resource always shows are rows even with nothing downloaded", () => {
    const rows = rows_for([family, single, mod], entries);
    expect(rows.find((r) => r.id == "fam:b")).toMatchObject({ downloaded: false, in_use: true, can_download: true, size: 0 });
    expect(rows.find((r) => r.id == "vad:vad")).toMatchObject({ downloaded: false, can_download: true });
  });

  test("files in a registered cache nobody claims are one Other files row per cache", () => {
    const other = rows_for([family, single, mod], entries).filter((r) => r.def == null);
    expect(other.map((r) => [r.id, r.files.map((f: any) => f.url), r.size])).toEqual([["other:c1", ["https://h/leftover.bin"], 7]]);
  });

  test("a resource that claims nothing and shows nothing is no row", () => {
    expect(rows_for([single], { c1: [] })).toEqual([]);
  });

  test("the caches to read are those registered, once each", () => {
    expect(caches_used([family, single, mod])).toEqual(["c1", "c2"]);
  });
});

describe("register_resource", () => {
  beforeEach(() => unregister_all());
  afterEach(() => unregister_all());
  test("needs an id, a cache and key(url)", () => {
    expect(() => register_resource({ id: "x" } as any)).toThrow(/needs id, cache and key/);
    register_resource({ id: "x", cache: "c", key: () => null });
    expect(registered().map((d) => d.id)).toEqual(["x"]);
  });
});

describe("cached_fetch", () => {
  test("fetches once, then answers from the cache, keeping the length", async () => {
    const store = memory_caches();
    const fetch_impl = vi.fn(async () => new Response("abcdef"));
    const r1 = await cached_fetch("c", "https://h/f", { store, fetch_impl });
    expect(await r1.text()).toBe("abcdef");
    const r2 = await cached_fetch("c", "https://h/f", { store, fetch_impl });
    expect(await r2.text()).toBe("abcdef");
    expect(fetch_impl).toHaveBeenCalledTimes(1);
    const kept = await (await store.open("c")).match("https://h/f");
    expect(kept!.headers.get("content-length")).toBe("6");
  });

  test("reports progress against the length the server gives", async () => {
    const store = memory_caches();
    const seen: any[] = [];
    const fetch_impl = async () => new Response("0123456789", { headers: { "content-length": "10" } });
    await cached_fetch("c", "https://h/f", { store, fetch_impl, onprogress: (l: number, t: number) => seen.push([l, t]) });
    expect(seen[0]).toEqual([0, 10]);
    expect(seen[seen.length - 1]).toEqual([10, 10]);
  });

  test("a failed fetch is an error and keeps nothing", async () => {
    const store = memory_caches();
    await expect(cached_fetch("c", "https://h/f", { store, fetch_impl: async () => new Response("", { status: 404 }) }))
      .rejects.toThrow(/HTTP 404/);
    expect(await (await store.open("c")).keys()).toEqual([]);
  });
});

describe("define_wasm_module", () => {
  let store: ReturnType<typeof memory_caches>;
  beforeEach(() => {
    unregister_all();
    store = memory_caches();
    vi.stubGlobal("caches", store);
    vi.stubGlobal("fetch", vi.fn(async (u: string) => new Response(`bytes of ${u}`, { headers: { "content-length": String(`bytes of ${u}`.length) } })));
  });
  afterEach(() => { vi.unstubAllGlobals(); unregister_all(); });

  test("registers a row that shows before it's downloaded, and downloads into the module cache", async () => {
    const m = define_wasm_module({ id: "vad", label: "Voice activity detector", description: "Finds speech",
      files: { wasm: "https://h/vad-1.0.wasm", glue: "https://h/vad-1.0.mjs" }, used_by: "sound-level segments" });
    let rows = rows_for(registered(), { [MODULE_CACHE]: [] });
    expect(rows[0]).toMatchObject({ id: "vad:vad", label: "Voice activity detector", downloaded: false, can_download: true });
    expect(rows[0].description).toBe("Finds speech — used by sound-level segments");

    const pct: any[] = [];
    await m.download({ onprogress: (p: any) => pct.push(p) });
    expect(pct[pct.length - 1]).toBe(100);
    const cached = (await (await store.open(MODULE_CACHE)).keys()).map((k: any) => k.url);
    expect(cached).toEqual(["https://h/vad-1.0.wasm", "https://h/vad-1.0.mjs"]);

    rows = rows_for(registered(), { [MODULE_CACHE]: cached.map((url: string) => ({ url, size: 1 })) });
    expect(rows[0]).toMatchObject({ downloaded: true, size: 2 });
  });

  test("bytes() gives a file's contents, downloading only what isn't kept", async () => {
    const m = define_wasm_module({ id: "x", label: "X", files: { wasm: "https://h/x.wasm" } });
    const b = new TextDecoder().decode(await m.bytes("wasm"));
    expect(b).toBe("bytes of https://h/x.wasm");
    await m.bytes("wasm");
    expect(fetch).toHaveBeenCalledTimes(1);
    await expect(m.bytes("nope")).rejects.toThrow(/no file called nope/);
  });

  test("files it didn't name aren't its", () => {
    define_wasm_module({ id: "x", label: "X", files: { wasm: "https://h/x-2.wasm" } });
    const rows = rows_for(registered(), { [MODULE_CACHE]: [{ url: "https://h/x-1.wasm", size: 3 }] });
    expect(rows.map((r) => r.id)).toEqual(["x:x", `other:${MODULE_CACHE}`]);
  });
});

test("the speech model cache is transformers.js's own", () => {
  expect(MODEL_CACHE).toBe("transformers-cache");
});
