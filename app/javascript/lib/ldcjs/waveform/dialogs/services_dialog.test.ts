import { render, screen } from "@testing-library/svelte";
import { tick } from "svelte";
import { beforeEach, describe, expect, test, vi } from "vitest";

// What this dialog offers is two independent questions, and they stopped
// agreeing once recognition could run in the page:
//
//   hosted services  need somewhere to send the audio, and permission to
//   in-browser ASR   needs a browser that can run a model
//
// The combinations that used to be impossible are the ones worth testing: a
// kit whose audio may not be sent but which can still be transcribed, and an
// instance with no HLT service at all that can still transcribe. Both used to
// be dead ends showing a notice.
//
// Mocked rather than driven through meta tags: this app defaults to no service
// at all, so a test that relied on the fallback would assert the absence of
// everything. The dialog's logic is what is under test, and it is the same
// whatever the fallback is.

const state = { services: true, local_audio: false, engine: true, energy: true };

vi.mock("../../service_config", () => ({
  services_configured: () => state.services,
  hlt_endpoint: () => "https://example.test",
  promise_bucket: () => "bucket",
  s3_configured: () => false
}));
vi.mock("../../local_audio", () => ({ local_audio_active: () => state.local_audio }));
vi.mock("../../local_asr", () => ({ local_asr_available: () => state.engine }));
vi.mock("../energy_run", () => ({ energy_available: () => state.energy }));

import ServicesDialog from "./ServicesDialog.svelte";

async function mount() {
  const r = render(ServicesDialog, { props: {} });
  await tick();
  return r;
}

beforeEach(() => {
  state.services = true;
  state.local_audio = false;
  state.engine = true;
  state.energy = true;
});

describe("ServicesDialog", () => {
  test("with both, the hosted services and the in-browser option are offered", async () => {
    await mount();
    expect(screen.getByText("SAD")).toBeTruthy();
    expect(screen.getByText("ASR")).toBeTruthy();
    expect(screen.getByText("ASR (in this browser)")).toBeTruthy();
  });

  test("a local_audio kit is no longer a dead end: it offers the in-browser option", async () => {
    state.local_audio = true;
    await mount();

    expect(screen.getByText("ASR (in this browser)")).toBeTruthy();
    // and not the services that would send the file away
    expect(screen.queryByText("SAD")).toBeNull();
    expect(screen.queryByText("ASR (Rev.ai)")).toBeNull();
    // with the reason, since an annotator expecting SAD should know which of
    // the two reasons applies
    expect(screen.getByText(/file on your computer/)).toBeTruthy();
  });

  test("an instance with no hosted service still offers the in-browser option", async () => {
    state.services = false;
    await mount();

    expect(screen.getByText("ASR (in this browser)")).toBeTruthy();
    expect(screen.queryByText("SAD")).toBeNull();
    expect(screen.getByText(/No hosted speech services are configured/)).toBeTruthy();
  });

  test("with none, the notice is shown and nothing is offered", async () => {
    state.services = false;
    state.engine = false;
    state.energy = false;
    await mount();

    expect(screen.queryByText("SAD")).toBeNull();
    expect(screen.queryByText("ASR (in this browser)")).toBeNull();
    expect(screen.getByText(/No speech services are configured on this server/)).toBeTruthy();
  });

  test("a local_audio kit in a browser that can do nothing itself keeps the old dead end", async () => {
    state.local_audio = true;
    state.engine = false;
    state.energy = false;
    await mount();

    expect(screen.queryByText("ASR (in this browser)")).toBeNull();
    expect(screen.getByText(/stays there,\s*so no speech services are available/)).toBeTruthy();
  });

  test("a browser that cannot run a model is not offered the option", async () => {
    state.engine = false;
    await mount();

    expect(screen.getByText("SAD")).toBeTruthy();
    expect(screen.queryByText("ASR (in this browser)")).toBeNull();
  });

  test("segments from sound level are offered wherever the browser can decode audio", async () => {
    await mount();
    expect(screen.getByText("Segments from sound level")).toBeTruthy();
  });

  test("including a local_audio kit, since nothing is sent", async () => {
    state.local_audio = true;
    await mount();
    expect(screen.getByText("Segments from sound level")).toBeTruthy();
    expect(screen.queryByText("SAD")).toBeNull();
  });

  test("and alone they are enough to make a menu rather than a notice", async () => {
    state.services = false;
    state.engine = false;
    await mount();
    expect(screen.getByText("Segments from sound level")).toBeTruthy();
    expect(screen.queryByText(/No speech services are configured on this server/)).toBeNull();
  });

  test("a browser that cannot decode audio is not offered them", async () => {
    state.energy = false;
    await mount();
    expect(screen.queryByText("Segments from sound level")).toBeNull();
  });

  test("filling empty segments is offered with the in-browser ASR", async () => {
    await mount();
    expect(screen.getByText("ASR into empty segments (in this browser)")).toBeTruthy();
  });

  test("and not without it", async () => {
    state.engine = false;
    await mount();
    expect(screen.queryByText("ASR into empty segments (in this browser)")).toBeNull();
  });
});
