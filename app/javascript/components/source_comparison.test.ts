import { describe, expect, test } from "vitest";
import { align_transcripts, normalize_text } from "./source_comparison";

const kit = (uid: string, user: string, segments: any[]) => ({ uid, user, segments });
const seg = (beg: number, end: number, text: string) => ({ beg, end, text });

// A block's lines as "user: text", which is how they read on screen.
const said = (row: any) => row.lines.map((l: any) => `${l.user}: ${l.text}`);

describe("align_transcripts", () => {
  test("each segment is its own line, labelled with its annotator", () => {
    const { columns, rows } = align_transcripts([
      kit("k1", "alice", [seg(0.5, 4.6, "that's carrie")]),
      kit("k2", "bob", [seg(0.6, 4.5, "that's Carrie")]),
    ]);
    expect(columns.map((c) => c.user)).toEqual(["alice", "bob"]);
    expect(rows).toHaveLength(1);
    expect(said(rows[0])).toEqual(["alice: that's carrie", "bob: that's Carrie"]);
    expect(rows[0].beg).toBe(0.5);
    expect(rows[0].end).toBe(4.6);
  });

  test("lines inside a block run in time order", () => {
    const { rows } = align_transcripts([
      kit("k1", "alice", [seg(2, 6, "alice later")]),
      kit("k2", "bob", [seg(1, 5, "bob first")]),
    ]);
    expect(said(rows[0])).toEqual(["bob: bob first", "alice: alice later"]);
  });

  test("non-overlapping segments become separate blocks, in time order", () => {
    const { rows } = align_transcripts([
      kit("k1", "alice", [seg(5, 6, "second"), seg(1, 2, "first")]),
    ]);
    expect(rows.map((r) => said(r))).toEqual([["alice: first"], ["alice: second"]]);
  });

  test("touching endpoints do not merge into one block", () => {
    const { rows } = align_transcripts([
      kit("k1", "alice", [seg(1, 2, "a")]),
      kit("k2", "bob", [seg(2, 3, "b")]),
    ]);
    expect(rows).toHaveLength(2);
  });

  test("an annotator who splits a span keeps one line per segment", () => {
    const { rows } = align_transcripts([
      kit("k1", "alice", [seg(0, 10, "the whole thing")]),
      kit("k2", "bob", [seg(0, 5, "the whole"), seg(5, 10, "thing")]),
    ]);
    expect(rows).toHaveLength(1);
    expect(said(rows[0])).toEqual([
      "alice: the whole thing",
      "bob: the whole",
      "bob: thing",
    ]);
    // …and splitting is not itself a disagreement
    expect(rows[0].differs).toBe(false);
  });

  test("a chain of overlaps merges transitively into one block", () => {
    const { rows } = align_transcripts([
      kit("k1", "alice", [seg(0, 4, "a")]),
      kit("k2", "bob", [seg(3, 7, "b")]),
      kit("k3", "carol", [seg(6, 10, "c")]),
    ]);
    expect(rows).toHaveLength(1);
    expect(rows[0].beg).toBe(0);
    expect(rows[0].end).toBe(10);
    expect(rows[0].lines).toHaveLength(3);
  });

  test("each line carries its own times", () => {
    const { rows } = align_transcripts([
      kit("k1", "alice", [seg(0.5, 4.6, "x")]),
      kit("k2", "bob", [seg(0.75, 4.25, "y")]),
    ]);
    expect(rows[0].lines.map((l: any) => [l.beg, l.end])).toEqual([
      [0.5, 4.6],
      [0.75, 4.25],
    ]);
  });

  test("differs flags a real disagreement but ignores case and punctuation", () => {
    const [same] = align_transcripts([
      kit("k1", "alice", [seg(0, 1, "Hello, there!")]),
      kit("k2", "bob", [seg(0, 1, "hello there")]),
    ]).rows;
    expect(same.differs).toBe(false);

    const [diff] = align_transcripts([
      kit("k1", "alice", [seg(0, 1, "hello there")]),
      kit("k2", "bob", [seg(0, 1, "hello where")]),
    ]).rows;
    expect(diff.differs).toBe(true);
  });

  test("a block only one annotator covered is a gap, not a disagreement", () => {
    const { rows } = align_transcripts([
      kit("k1", "alice", [seg(0, 1, "only alice")]),
      kit("k2", "bob", []),
    ]);
    expect(rows[0].present).toBe(1);
    expect(rows[0].differs).toBe(false);
    expect(said(rows[0])).toEqual(["alice: only alice"]);
  });

  test("empty text does not count as a competing version", () => {
    const { rows } = align_transcripts([
      kit("k1", "alice", [seg(0, 1, "something")]),
      kit("k2", "bob", [seg(0, 1, "   ")]),
    ]);
    expect(rows[0].present).toBe(1);
    expect(rows[0].differs).toBe(false);
    // the empty segment still gets its own line — it exists in bob's transcript
    expect(rows[0].lines).toHaveLength(2);
  });

  test("segments with null times (a done kit with no transcript) are dropped", () => {
    const { columns, rows } = align_transcripts([
      kit("k1", "alice", [seg(0, 1, "real")]),
      kit("k2", "bob", [{ beg: null, end: null, text: null }]),
    ]);
    expect(columns).toHaveLength(2); // bob is still listed as an annotator
    expect(rows).toHaveLength(1);
    expect(said(rows[0])).toEqual(["alice: real"]);
  });

  test("string times from the JSON payload are handled", () => {
    const { rows } = align_transcripts([
      kit("k1", "alice", [{ beg: "0.5", end: "4.6", text: "x" } as any]),
    ]);
    expect(rows[0].beg).toBe(0.5);
    expect(rows[0].lines[0].beg).toBe(0.5);
  });

  test("an end before its beg doesn't swallow later blocks", () => {
    const { rows } = align_transcripts([
      kit("k1", "alice", [{ beg: 5, end: 1, text: "backwards" }, seg(6, 7, "after")]),
    ]);
    expect(rows).toHaveLength(2);
  });

  test("no kits yields no columns and no rows", () => {
    expect(align_transcripts([])).toEqual({ columns: [], rows: [] });
    expect(align_transcripts(undefined as any)).toEqual({ columns: [], rows: [] });
  });
});

describe("normalize_text", () => {
  test("collapses case, punctuation and whitespace but keeps apostrophes", () => {
    expect(normalize_text("  That's,   CARRIE! ")).toBe("that's carrie");
  });

  test("null and undefined become the empty string", () => {
    expect(normalize_text(null as any)).toBe("");
    expect(normalize_text(undefined as any)).toBe("");
  });
});
