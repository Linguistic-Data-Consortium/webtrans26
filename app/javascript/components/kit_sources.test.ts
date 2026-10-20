import { describe, expect, test } from "vitest";
import { aggregate_sources } from "./kit_sources";

// The Sources tab rolls the task's kit list up per source: how many distinct
// users have completed (state 'done') at least one kit for each source.
const kit = (source_uid: string, state: string, user: string) =>
  ({ source_uid, state, user });

describe("aggregate_sources", () => {
  test("counts distinct users with a done kit, and names them", () => {
    const rows = aggregate_sources([
      kit("s3://b/one.wav", "done", "alice"),
      kit("s3://b/one.wav", "done", "bob"),
      kit("s3://b/one.wav", "assigned", "charlie"),
    ]);
    expect(rows).toEqual([
      { source: "s3://b/one.wav", kits: 3, done_kits: 2, done_users: 2, users: "alice, bob" },
    ]);
  });

  test("a user with several done kits on one source counts once", () => {
    const [row] = aggregate_sources([
      kit("a.wav", "done", "alice"),
      kit("a.wav", "done", "alice"),
    ]);
    expect(row.done_users).toBe(1);
    expect(row.done_kits).toBe(2);
    expect(row.users).toBe("alice");
  });

  test("a source with no done kits still gets a row, with zero users", () => {
    const [row] = aggregate_sources([kit("a.wav", "assigned", "alice")]);
    expect(row).toEqual({ source: "a.wav", kits: 1, done_kits: 0, done_users: 0, users: "" });
  });

  test("the 'none' username of an unassigned kit is not counted as a user", () => {
    const [row] = aggregate_sources([kit("a.wav", "done", "none")]);
    expect(row.done_users).toBe(0);
    expect(row.done_kits).toBe(1);
  });

  test("kits with no source are grouped under 'none'", () => {
    const rows = aggregate_sources([
      { state: "done", user: "alice" },
      { source_uid: "", state: "done", user: "bob" },
    ] as any);
    expect(rows.map((r) => r.source)).toEqual(["none"]);
    expect(rows[0].done_users).toBe(2);
  });

  test("one row per source, sorted by source", () => {
    const rows = aggregate_sources([
      kit("c.wav", "done", "alice"),
      kit("a.wav", "done", "bob"),
      kit("b.wav", "broken", "bob"),
    ]);
    expect(rows.map((r) => r.source)).toEqual(["a.wav", "b.wav", "c.wav"]);
  });

  test("names are listed alphabetically and de-duplicated across kits", () => {
    const [row] = aggregate_sources([
      kit("a.wav", "done", "carol"),
      kit("a.wav", "done", "alice"),
      kit("a.wav", "done", "carol"),
    ]);
    expect(row.users).toBe("alice, carol");
    expect(row.done_users).toBe(2);
  });

  test("an empty kit list yields no rows", () => {
    expect(aggregate_sources([])).toEqual([]);
    expect(aggregate_sources(undefined as any)).toEqual([]);
  });
});
