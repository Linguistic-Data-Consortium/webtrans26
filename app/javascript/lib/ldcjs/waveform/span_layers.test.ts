import { beforeEach, describe, expect, test } from "vitest";
import { bands_in_window, by_channel, next_color, PALETTE } from "./span_geometry";
import {
  span_layers, use_store, load_previews, add_layer, update_layer, remove_layer,
  select_span, selected_span, list_all_previews, clear_previews
} from "./span_layers.svelte";

describe("bands_in_window", () => {
  const spans = [{ beg: 1, end: 2 }, { beg: 9, end: 12 }, { beg: 20, end: 21 }, { beg: 5, end: 5.001 }];

  test("only what shows, in pixels from the window's left edge, clipped to it", () => {
    // a 10 s window from 2 s, 1000 px wide: 100 px a second
    expect(bands_in_window(spans, 2, 10, 1000)).toEqual([
      { i: 1, left: 700, width: 300 },
      { i: 3, left: 300, width: 1 }
    ]);
  });

  test("a span that only touches the edge isn't drawn", () => {
    expect(bands_in_window([{ beg: 0, end: 2 }], 2, 10, 1000)).toEqual([]);
  });

  test("no window, nothing drawn", () => {
    expect(bands_in_window(spans, 0, 0, 1000)).toEqual([]);
    expect(bands_in_window(spans, 0, 10, 0)).toEqual([]);
  });
});

describe("by_channel", () => {
  test("a bar per channel, in the kit's docid order, each span keeping its index", () => {
    const g = by_channel([{ beg: 0, end: 1, docid: "f:B" }, { beg: 1, end: 2, docid: "f:A" }, { beg: 2, end: 3, docid: "f:B" }], ["f:A", "f:B"]);
    expect(g.map((c) => [c.docid, c.segments.map((s) => s.i)])).toEqual([["f:A", [1]], ["f:B", [0, 2]]]);
  });
});

describe("colours", () => {
  test("the next unused colour, then round again", () => {
    expect(next_color([])).toBe(PALETTE[0]);
    expect(next_color([{ color: PALETTE[0] }, { color: PALETTE[2] }])).toBe(PALETTE[1]);
    expect(next_color(PALETTE.map((color) => ({ color })))).toBe(PALETTE[0]);
  });
});

describe("layers", () => {
  // IndexedDB stand-in: structured clone, so a proxy would fail here as it
  // does in the browser.
  let saved: Map<string, any>;
  beforeEach(async () => {
    saved = new Map();
    use_store({
      get: async (k: string) => saved.has(k) ? structuredClone(saved.get(k)) : undefined,
      put: async (k: string, v: any) => { saved.set(k, structuredClone(v)); },
      delete: async (k: string) => { saved.delete(k); },
      keys: async () => [...saved.keys()]
    });
    await load_previews("kit-1");
  });

  test("a layer is kept for its kit, shown, coloured, its spans in time order", async () => {
    const l = await add_layer({ label: "run 1", source: "energy", segments: [{ beg: 5, end: 6, docid: "d" }, { beg: 1, end: 2, docid: "d" }] });
    expect(l).toMatchObject({ label: "run 1", visible: true, color: PALETTE[0] });
    expect(l.segments.map((s: any) => s.beg)).toEqual([1, 5]);
    expect(saved.get("kit-1").map((x: any) => x.label)).toEqual(["run 1"]);
  });

  test("they come back on load, and another kit's are its own", async () => {
    await add_layer({ label: "a", segments: [] });
    await add_layer({ label: "b", segments: [] });
    await load_previews("kit-2");
    expect(span_layers.layers).toEqual([]);
    await load_previews("kit-1");
    expect(span_layers.layers.map((l) => l.label)).toEqual(["a", "b"]);
    expect(span_layers.layers.map((l) => l.color)).toEqual([PALETTE[0], PALETTE[1]]);
  });

  test("hidden, renamed and removed, each kept", async () => {
    const a = await add_layer({ label: "a", segments: [] });
    const b = await add_layer({ label: "b", segments: [] });
    await update_layer(a.id, { visible: false, label: "a2" });
    await remove_layer(b.id);
    expect(saved.get("kit-1").map((x: any) => [x.label, x.visible])).toEqual([["a2", false]]);
  });

  test("a selected span is found by layer and index, and goes with its layer", async () => {
    const a = await add_layer({ label: "a", segments: [{ beg: 1, end: 2, docid: "d" }, { beg: 3, end: 4, docid: "d" }] });
    select_span(a.id, 1);
    expect(selected_span()?.span).toMatchObject({ beg: 3, end: 4 });
    await remove_layer(a.id);
    expect(selected_span()).toBeNull();
  });

  // The store is for any feature: nothing about it is sound-level's.
  test("a layer from any source, its spans' extra fields kept", async () => {
    const l = await add_layer({ label: "ASR words", source: "asr", segments: [{ beg: 0.5, end: 0.9, docid: "d", text: "hello", confidence: 0.8 }] });
    expect(saved.get("kit-1")[0]).toMatchObject({ label: "ASR words", source: "asr" });
    expect(l.segments[0]).toMatchObject({ text: "hello", confidence: 0.8 });
  });

  test("a bad span is refused, naming it, and nothing is kept", async () => {
    await expect(add_layer({ label: "x", segments: [{ beg: 0, end: 1, docid: "d" }, { beg: 2, end: 1, docid: "d" }] }))
      .rejects.toThrow('span 1 of "x": ends before it begins');
    await expect(add_layer({ label: "y", segments: [{ beg: 0, end: 1 }] })).rejects.toThrow('span 0 of "y": no docid');
    await expect(add_layer({ label: "", segments: [] })).rejects.toThrow("needs a label");
    await expect(add_layer({ label: "z" } as any)).rejects.toThrow("needs segments");
    expect(span_layers.layers).toEqual([]);
    expect(saved.has("kit-1")).toBe(false);
  });

  test("listed per kit for the resources dialog, and cleared", async () => {
    await add_layer({ label: "a", segments: [{ beg: 1, end: 2, docid: "d" }, { beg: 3, end: 4, docid: "d" }] });
    await load_previews("kit-2");
    await add_layer({ label: "b", segments: [{ beg: 1, end: 2, docid: "d" }] });
    expect(await list_all_previews()).toEqual([{ kit: "kit-1", layers: 1, spans: 2 }, { kit: "kit-2", layers: 1, spans: 1 }]);
    await clear_previews("kit-2");
    expect(span_layers.layers).toEqual([]);
    expect([...saved.keys()]).toEqual(["kit-1"]);
  });
});
