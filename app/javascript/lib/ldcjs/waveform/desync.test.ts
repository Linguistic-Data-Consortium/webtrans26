import { beforeEach, describe, expect, test, vi } from "vitest";
import { desync, report_desync, desynced, desync_clear } from "./desync.svelte";

// Every write is applied locally before it is posted, so the client's state is a
// prediction. When the server's reply disagrees, the prediction lost and the
// page is showing something that isn't recorded — which the annotator has to be
// told, because there is no way back except a reload.
describe("desync reporting", () => {
  beforeEach(() => {
    desync_clear();
    vi.spyOn(console, "error").mockImplementation(() => {});
  });

  test("nothing is wrong to begin with", () => {
    expect(desynced()).toBe(false);
    expect(desync.reason).toBe(null);
  });

  test("a report sets a reason an annotator can act on", () => {
    report_desync("A change didn't save as typed.", { index: 3 });

    expect(desynced()).toBe(true);
    expect(desync.reason).toBe("A change didn't save as typed.");
    expect(desync.detail).toEqual({ index: 3 });
  });

  // One divergence usually makes several messages fail in a row. The first is
  // the one nearest the cause, and the banner shows one reason, so later
  // reports must not overwrite it.
  test("the first report wins", () => {
    report_desync("first", { n: 1 });
    report_desync("second", { n: 2 });

    expect(desync.reason).toBe("first");
    expect(desync.detail).toEqual({ n: 1 });
  });

  test("the detail goes to the console, not the banner", () => {
    const err = vi.spyOn(console, "error").mockImplementation(() => {});
    report_desync("A change was refused by the server.", { error: "boom" });

    expect(err).toHaveBeenCalledWith(
      expect.stringContaining("A change was refused by the server."),
      { error: "boom" },
    );
  });

  test("a report with no detail still logs", () => {
    const err = vi.spyOn(console, "error").mockImplementation(() => {});
    report_desync("something");

    expect(err).toHaveBeenCalledWith(expect.stringContaining("something"), "");
  });

  test("clearing resets it", () => {
    report_desync("something", { a: 1 });
    desync_clear();

    expect(desynced()).toBe(false);
    expect(desync.detail).toBe(null);
  });
});

// The regression that made the whole check untrustworthy. Responses used to be
// paired with sent messages through one monotonic counter across every request.
// A failed request recorded its messages as sent and never answered them, so
// the counter fell permanently behind: from then on every reply was compared
// against the wrong message, reporting mismatches that weren't real.
//
// Pairing is per-request now — by position within `submissions[client_time]` —
// so a dropped request can't shift anything. This models both schemes to show
// the difference, since the real pairing lives inside modification2.js's
// annotate2 and isn't exported.
describe("pairing survives a dropped request", () => {
  const pair_by_counter = (requests: string[][][]) => {
    const sent: string[] = [];
    let counter = -1;
    const pairs: Array<[string, string]> = [];
    for (const [outgoing, replies] of requests) {
      sent.push(...outgoing);
      for (const r of replies) pairs.push([sent[++counter], r]);
    }
    return pairs;
  };

  const pair_by_request = (requests: string[][][]) => {
    const pairs: Array<[string, string]> = [];
    for (const [outgoing, replies] of requests) {
      replies.forEach((r, i) => pairs.push([outgoing[i], r]));
    }
    return pairs;
  };

  // Request one sends two messages and gets no reply; request two sends one and
  // is answered.
  const dropped = [
    [["a", "b"], []],
    [["c"], ["c"]],
  ] as string[][][];

  test("the old counter scheme pairs the reply with a stale message", () => {
    expect(pair_by_counter(dropped)).toEqual([["a", "c"]]);
  });

  test("per-request pairing keeps them aligned", () => {
    expect(pair_by_request(dropped)).toEqual([["c", "c"]]);
  });

  test("both agree when nothing is dropped", () => {
    const clean = [
      [["a", "b"], ["a", "b"]],
      [["c"], ["c"]],
    ] as string[][][];

    expect(pair_by_request(clean)).toEqual(pair_by_counter(clean));
  });
});
