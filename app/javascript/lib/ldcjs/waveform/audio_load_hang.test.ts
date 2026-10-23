import { describe, expect, test, vi } from "vitest";
import { getp_wav } from "../../../../../test/javascript/mocks/ldcjs-getp";

// helpers.js reaches modification1.js, which imports the guide module — and
// that assigns to window.Guide at import time, which jsdom has nothing for.
// Stubbing it is cheaper than loading the whole guide machinery to test a
// promise's rejection.
vi.mock("../../../guides/guide", () => ({
  event: { dispatch: () => {}, listen: () => {} },
  default: {}
}));

import { get_audio_buffer_info } from "./helpers";

// get_audio_buffer_info used to wrap its whole chain in a `new Promise` with
// no .catch, so every failure left that promise unsettled — and the waveform's
// {#await} sat on "loading audio" for ever, with the real error only in the
// console. These are the two ways that happened in practice. Both must now
// reject: what the UI does with the rejection is its business, but a promise
// that never settles can't be reported at all.
describe("a failed audio load rejects rather than hanging", () => {
  const ldc = (urls: any) => ({ resources: { urls } });

  test("a range read that came back empty — which is what getp_wav returns on any error", async () => {
    vi.mocked(getp_wav).mockResolvedValueOnce(undefined as any);
    await expect(get_audio_buffer_info("a.wav", ldc({ "a.wav": "https://x.test/a.wav" })))
      .rejects.toBeDefined();
  });

  test("a docid with no url to read, where resolving the source yields nothing", async () => {
    await expect(get_audio_buffer_info("missing.wav", ldc({})))
      .rejects.toBeDefined();
  });
});
