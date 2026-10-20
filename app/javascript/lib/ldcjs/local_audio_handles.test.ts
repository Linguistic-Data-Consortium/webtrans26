import { describe, expect, test } from "vitest";
import { reopen_saved, read_handle } from "./local_audio_handles";

// What a returning local_audio kit does with the handle it saved. The store is
// passed in, so these use a Map where the page uses IndexedDB.
function fake_store(entries: Record<string, any> = {}) {
  const m = new Map(Object.entries(entries));
  return {
    map: m,
    get: async (k: string) => m.get(k),
    put: async (k: string, v: any) => { m.set(k, v); },
    delete: async (k: string) => { m.delete(k); },
  };
}

function handle(opts: { permission?: string, file?: File, gone?: boolean } = {}) {
  return {
    queryPermission: async () => opts.permission ?? "granted",
    getFile: async () => {
      if (opts.gone) throw new DOMException("gone", "NotFoundError");
      return opts.file;
    },
  };
}

const wav = (name: string, n: number) => new File([ new Uint8Array(n) ], name);

describe("reopen_saved", () => {
  test("nothing saved means ask as usual", async () => {
    expect(await reopen_saved(fake_store(), "k1", "a.wav", 10)).toBeNull();
  });

  test("a store that fails means ask as usual", async () => {
    const store = { ...fake_store(), get: async () => { throw new Error("no idb"); } };
    expect(await reopen_saved(store, "k1", "a.wav", 10)).toBeNull();
  });

  test("still allowed and the same file: carries on with it", async () => {
    const file = wav("a.wav", 10);
    const h = handle({ file });
    const r = await reopen_saved(fake_store({ k1: h }), "k1", "a.wav", 10);
    expect(r).toEqual({ file, handle: h });
  });

  test("needing permission again asks for a click, and keeps the handle", async () => {
    const h = handle({ permission: "prompt", file: wav("a.wav", 10) });
    const store = fake_store({ k1: h });
    expect(await reopen_saved(store, "k1", "a.wav", 10)).toEqual({ handle: h, ask: true });
    expect(store.map.has("k1")).toBe(true);
  });

  test("a file that's gone is forgotten, with a reason", async () => {
    const store = fake_store({ k1: handle({ gone: true }) });
    const r = await reopen_saved(store, "k1", "a.wav", 10);
    expect(r.error).toMatch(/moved or deleted/);
    expect(store.map.has("k1")).toBe(false);
  });

  test("a file that changed size is forgotten, with a reason", async () => {
    const store = fake_store({ k1: handle({ file: wav("a.wav", 11) }) });
    const r = await reopen_saved(store, "k1", "a.wav", 10);
    expect(r.error).toMatch(/11 bytes.*10 bytes/);
    expect(store.map.has("k1")).toBe(false);
  });
});

describe("read_handle", () => {
  test("is the check behind the one-click reopen too", async () => {
    const file = wav("a.wav", 10);
    const h = handle({ file });
    expect(await read_handle(fake_store(), "k1", h, "a.wav", 10)).toEqual({ file, handle: h });
  });
});
