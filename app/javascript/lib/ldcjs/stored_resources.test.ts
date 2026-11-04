import { describe, expect, test } from "vitest";
import { read_cache, delete_cache_files, format_bytes, read_settings, reset_setting } from "./stored_resources";
import {
  asr_model, server_model, server_language, chosen_size, choose_size, chosen_language, choose_language,
  run_language, model_for, model_label, ASR_SIZES
} from "./local_asr";
import { afterEach } from "vitest";

// A stand-in for the Cache API, one named cache: enough to list, size and delete.
export function fake_caches(name: string, entries: Record<string, { body: string, length?: boolean }>) {
  const store = new Map(Object.entries(entries));
  const cache = {
    keys: async () => [...store.keys()].map((url) => ({ url })),
    match: async (req: any) => {
      const e = store.get(req.url ?? req);
      if (!e) return undefined;
      const headers = new Headers(e.length === false ? {} : { "content-length": String(e.body.length) });
      return new Response(e.body, { headers });
    },
    delete: async (url: string) => store.delete(url)
  };
  return { store, has: async (n: string) => n === name, open: async () => cache };
}

describe("reading and deleting a cache", () => {
  test("sizes come from Content-Length, or from the body when there is none", async () => {
    const c = fake_caches("c", { "https://h/x": { body: "12345" }, "https://h/y": { body: "123", length: false } });
    expect((await read_cache("c", c as any)).map((e) => e.size)).toEqual([5, 3]);
  });

  test("a cache that isn't there reads as empty", async () => {
    expect(await read_cache("other", fake_caches("c", {}) as any)).toEqual([]);
    expect(await read_cache("c", null as any)).toEqual([]);
  });

  test("deleting removes exactly the files named", async () => {
    const c = fake_caches("c", { a: { body: "1" }, b: { body: "2" }, c: { body: "3" } });
    await delete_cache_files("c", ["a", "c"], c as any);
    expect([...c.store.keys()]).toEqual(["b"]);
  });
});

describe("format_bytes", () => {
  test("in the unit that reads", () => {
    expect(format_bytes(null)).toBe("–");
    expect(format_bytes(512)).toBe("512 B");
    expect(format_bytes(1536)).toBe("1.5 KB");
    expect(format_bytes(23201320)).toBe("22 MB");
    expect(format_bytes(3 * 1024 ** 3)).toBe("3.0 GB");
  });
});

describe("which model", () => {
  afterEach(() => {
    choose_size(null);
    choose_language(null);
    document.head.querySelectorAll('meta[name="asr-model"], meta[name="asr-language"]').forEach((el) => el.remove());
  });
  const meta = (name: string, content: string) => {
    const m = document.createElement("meta");
    m.setAttribute("name", name);
    m.setAttribute("content", content);
    document.head.appendChild(m);
  };

  test("by default, base in English: the English-only model", () => {
    expect(asr_model()).toBe("onnx-community/whisper-base.en");
    expect(run_language()).toBeNull();
  });

  test("another language runs the multilingual model of the size, told the language", () => {
    choose_language("French");
    expect(asr_model()).toBe("onnx-community/whisper-base");
    expect(run_language()).toBe("fr");
    choose_size("small");
    expect(asr_model()).toBe("onnx-community/whisper-small");
  });

  test("the server gives the size and the language; this browser's choices win", () => {
    meta("asr-model", "onnx-community/whisper-tiny.en");
    meta("asr-language", "de");
    expect(server_model()).toBe("onnx-community/whisper-tiny.en");
    expect(server_language()).toBe("de");
    expect(asr_model()).toBe("onnx-community/whisper-tiny");
    expect(run_language()).toBe("de");
    choose_language("en");
    expect(asr_model()).toBe("onnx-community/whisper-tiny.en");
    choose_size("base");
    expect(asr_model()).toBe("onnx-community/whisper-base.en");
    choose_size(null);
    choose_language(null);
    expect(chosen_size()).toBeNull();
    expect(asr_model()).toBe("onnx-community/whisper-tiny");
  });

  test("a deployment's own model is used as named", () => {
    expect(model_for({ server: "someone/whisper-large-v3-turbo", language: "fr" })).toBe("someone/whisper-large-v3-turbo");
    expect(model_for({ server: "someone/whisper-large-v3-turbo", size: "tiny", language: "fr" })).toBe("onnx-community/whisper-tiny");
  });

  test("a language Whisper doesn't know is refused, and nothing is kept", () => {
    expect(() => choose_language("Klingon")).toThrow(/doesn't know the language "Klingon"/);
    expect(chosen_language()).toBeNull();
  });

  test("models are named by size and kind", () => {
    expect(model_label("onnx-community/whisper-small.en")).toBe("Whisper small (English)");
    expect(model_label("onnx-community/whisper-base")).toBe("Whisper base (multilingual)");
    expect(model_label("someone/other")).toBe("someone/other");
    expect(ASR_SIZES.map((z) => z.id)).toEqual(["tiny", "base", "small"]);
  });
});

describe("settings", () => {
  test("listed with their values, and reset one at a time", () => {
    localStorage.setItem("energy_segments", '{"margin_db":12}');
    expect(read_settings().find((s) => s.key == "energy_segments")?.value).toBe('{"margin_db":12}');
    reset_setting("energy_segments");
    expect(read_settings().find((s) => s.key == "energy_segments")?.value).toBeNull();
  });
});
