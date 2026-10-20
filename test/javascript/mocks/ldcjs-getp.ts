import { vi } from "vitest";

// A tiny, controllable `getp` stub that tests can override per-call via:
//   import { getp } from "../../test/javascript/mocks/ldcjs-getp";
//   vi.mocked(getp).mockResolvedValueOnce({ authenticated: true, ... });
export const getp = vi.fn(() => Promise.resolve({}));
export const postp = vi.fn(() => Promise.resolve({}));
export const patchp = vi.fn(() => Promise.resolve({}));
export const deletep = vi.fn(() => Promise.resolve({}));
export const getp_no_catch = vi.fn(() => Promise.resolve({}));
export const postp_no_catch = vi.fn(() => Promise.resolve({}));
export const postpf_no_catch = vi.fn(() => Promise.resolve({}));
export const getp_wav = vi.fn(() => Promise.resolve(new ArrayBuffer(0)));
export const getp_simple = vi.fn(() => Promise.resolve({}));
