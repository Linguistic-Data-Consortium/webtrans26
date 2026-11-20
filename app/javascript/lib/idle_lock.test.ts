import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { start_idle_lock, KEY } from "./idle_lock";

// The screen lock (idle_lock.js), with the clock and storage under test control.
let t = 0;
const now = () => t;
let watcher: ReturnType<typeof start_idle_lock>;
const lock = vi.fn();
const storage = new Map<string, string>();
const store = { getItem: (k: string) => storage.get(k) ?? null, setItem: (k: string, v: string) => { storage.set(k, v); } };

beforeEach(() => {
  t = 1_000_000;
  storage.clear();
  lock.mockReset();
  watcher = start_idle_lock({ seconds: 1800, lock, now, storage: store, check_every_ms: 1e9 });
});
afterEach(() => watcher?.stop());

const press = () => window.dispatchEvent(new KeyboardEvent("keydown", { key: "a" }));

test("nothing happens before the limit", () => {
  t += 1799 * 1000;
  expect(watcher!.check()).toBe(false);
  expect(lock).not.toHaveBeenCalled();
});

test("at the limit with no input, the screen locks, once", () => {
  t += 1800 * 1000;
  expect(watcher!.check()).toBe(true);
  watcher!.check();
  expect(lock).toHaveBeenCalledTimes(1);
});

test("input resets the clock", () => {
  t += 1700 * 1000;
  press();
  t += 1700 * 1000;
  expect(watcher!.check()).toBe(false);
});

test("activity in another tab counts here, so a background tab doesn't sign out the one in use", () => {
  t += 1700 * 1000;
  store.setItem(KEY, String(t)); // the other tab wrote it
  t += 1700 * 1000;
  expect(watcher!.check()).toBe(false);
});

test("a tab coming back into view is checked at once, not at the next tick", () => {
  t += 1801 * 1000;
  document.dispatchEvent(new Event("visibilitychange"));
  expect(lock).toHaveBeenCalledTimes(1);
});

test("a signed-out page, with no limit, isn't watched", () => {
  expect(start_idle_lock({ seconds: NaN, lock })).toBeNull();
  expect(start_idle_lock({ seconds: 0, lock })).toBeNull();
});
