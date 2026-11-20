import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

// What happens to saves when one fails (modification2.js save_failed).
const post = vi.fn();
const check = vi.fn();
vi.mock("../getp", () => ({
  postp: vi.fn(),
  postp_no_catch: (...a: unknown[]) => post(...a),
  getp_no_catch: (...a: unknown[]) => check(...a),
}));

// Fresh modules for every test: the save queue is module state, and a test
// that leaves it holding would hold every test after it.
let m: typeof import("./modification2");
let d: typeof import("./desync.svelte");
let h: typeof import("./session_hold.svelte");

// annotate2 walks replies with jQuery's $.each; nothing else of it is reached.
(globalThis as any).$ = { each: (a: any[], f: (i: number, x: any) => void) => a.forEach((x, i) => f(i, x)) };

const settle = () => new Promise((r) => setTimeout(r, 0));
const sent = () => post.mock.calls.map((c) => JSON.parse(c[1].json).messages.map((m: any) => m.node));
const save = (node: number) => { m.add_message(node, "delete", null); m.submit_form(); };
const expired = Object.assign(new Error("response error"), { status: 401, session_expired: true });
const broken = Object.assign(new Error("response error"), { status: 500, session_expired: false });

describe("the save queue", () => {
  beforeEach(async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    vi.spyOn(console, "log").mockImplementation(() => {});
    vi.resetModules();
    m = await import("./modification2");
    d = await import("./desync.svelte");
    h = await import("./session_hold.svelte");
    post.mockReset().mockResolvedValue([{ message: "delete" }]);
    check.mockReset();
    m.setldc({ obj2: { _id: "kit", task_user_id: 7, read_only: false } });
  });

  afterEach(() => h.session_hold_reset());

  test("normally, each save goes out once, in order, as it always did", async () => {
    save(5); save(6);
    await settle(); await settle();
    expect(sent()).toEqual([[5], [6]]);
    expect(JSON.parse(post.mock.calls[0][1].json)).toMatchObject({ kit_uid: "kit", messages: [{ node: 5, message: "delete" }] });
    expect(post.mock.calls[0][1].task_user_id).toBe(7);
    expect(d.desynced()).toBe(false);
  });

  test("signed out: the save is held, later ones wait behind it, and nothing is reported as lost", async () => {
    post.mockRejectedValueOnce(expired);
    save(5); save(6);
    await settle(); await settle();
    expect(sent()).toEqual([[5]]);
    expect(h.session_hold.held).toBe(true);
    expect(d.desynced()).toBe(false);
  });

  test("still signed out: checking keeps holding", async () => {
    post.mockRejectedValueOnce(expired);
    check.mockRejectedValue(expired);
    save(5);
    await settle();
    expect(await h.try_resume()).toBe(false);
    expect(h.session_hold.held).toBe(true);
  });

  test("signed in again: the held save is resent unchanged, then the rest, in order", async () => {
    post.mockRejectedValueOnce(expired);
    save(5); save(6); save(7);
    await settle();
    check.mockResolvedValue({ time: "now" });
    expect(await h.try_resume()).toBe(true);
    for (let i = 0; i < 6; i++) await settle();
    expect(sent()).toEqual([[5], [5], [6], [7]]);
    expect(post.mock.calls[1][1]).toEqual(post.mock.calls[0][1]);
    expect(h.session_hold.held).toBe(false);
    expect(d.desynced()).toBe(false);
  });

  test("any other failure is reported, and later saves still go out", async () => {
    post.mockRejectedValueOnce(broken);
    save(5); save(6);
    for (let i = 0; i < 4; i++) await settle();
    expect(d.desynced()).toBe(true);
    expect(sent()).toEqual([[5], [6]]);
  });

  test("a reply that can't be checked doesn't stop the queue either", async () => {
    post.mockResolvedValueOnce("not a list of replies");
    save(5); save(6);
    for (let i = 0; i < 4; i++) await settle();
    expect(sent()).toEqual([[5], [6]]);
  });
});
