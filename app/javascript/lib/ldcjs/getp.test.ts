import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { getp_no_catch } from "./getp";

// How a failed response is described to the caller (getp.js response_error):
// the save queue holds edits when the session has ended, and reports anything
// else, so the two have to be told apart.
const reply = (o: Partial<Response> & { type?: string }) => ({
  ok: false, status: 200, redirected: false, url: "http://app.test/annotations",
  headers: new Headers(o.type ? { "content-type": o.type } : {}),
  json: async () => ({ ok: true }), ...o,
});

beforeEach(() => {
  document.head.innerHTML = '<meta name="csrf-token" content="t">';
});
afterEach(() => vi.unstubAllGlobals());

const failure = async (r: object) => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue(r));
  return getp_no_catch("/x").then(() => null, (e) => e);
};

test("a 401 means the session ended", async () => {
  const e = await failure(reply({ status: 401 }));
  expect(e).toMatchObject({ status: 401, session_expired: true });
});

test("landing on the sign-in form after a redirect means the session ended, though the status is ok", async () => {
  const e = await failure(reply({ ok: true, redirected: true, url: "http://app.test/session/new", type: "text/html" }));
  expect(e).toMatchObject({ session_expired: true });
});

test("a server error is just a failure", async () => {
  const e = await failure(reply({ status: 500 }));
  expect(e).toMatchObject({ status: 500, session_expired: false });
});

test("an ordinary JSON reply still comes through", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue(reply({ ok: true, type: "application/json" })));
  expect(await getp_no_catch("/x")).toEqual({ ok: true });
});
