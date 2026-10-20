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
// Mocked rather than driven through meta tags, because the fallbacks differ
// between the apps this file is copied into: wta defaults to LDC's service,
// the public release defaults to none. The dialog's logic is the same either
// way, and that is what is under test.

const state = { services: true, local_audio: false, engine: true };

vi.mock("../../service_config", () => ({
  services_configured: () => state.services,
  hlt_endpoint: () => "https://example.test",
  promise_bucket: () => "bucket",
  s3_configured: () => false
}));
vi.mock("../../local_audio", () => ({ local_audio_active: () => state.local_audio }));
vi.mock("../../local_asr", () => ({ local_asr_available: () => state.engine }));

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

  test("with neither, the notice is shown and nothing is offered", async () => {
    state.services = false;
    state.engine = false;
    await mount();

    expect(screen.queryByText("SAD")).toBeNull();
    expect(screen.queryByText("ASR (in this browser)")).toBeNull();
    expect(screen.getByText(/No speech services are configured on this server/)).toBeTruthy();
  });

  test("a local_audio kit in a browser that cannot run a model keeps the old dead end", async () => {
    state.local_audio = true;
    state.engine = false;
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
});
