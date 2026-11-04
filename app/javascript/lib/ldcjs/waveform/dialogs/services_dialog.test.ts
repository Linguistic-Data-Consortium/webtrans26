import { render, screen } from "@testing-library/svelte";
import { tick } from "svelte";
import { beforeEach, describe, expect, test, vi } from "vitest";

// Everything this dialog offers runs in the annotator's own browser, so what
// it shows turns on two questions about the browser rather than on anything
// the server has configured:
//
//   engine  can it run a speech model?
//   energy  can it decode audio, to find segments from the sound level?
//
// Either alone is a usable menu; only when both are false is there a notice.
//
// The hosted services -- SAD and the three remote ASR engines, numbered 1 to 4
// -- are not offered in this app at all, and the last test here is what keeps
// it that way: they are gone from the markup, not merely hidden, so no
// configuration can bring them back.

const state = { engine: true, energy: true };

vi.mock("../../local_asr", () => ({ local_asr_available: () => state.engine }));
vi.mock("../energy_run", () => ({ energy_available: () => state.energy }));

import ServicesDialog from "./ServicesDialog.svelte";

async function mount() {
  const r = render(ServicesDialog, { props: {} });
  await tick();
  return r;
}

beforeEach(() => {
  state.engine = true;
  state.energy = true;
});

describe("ServicesDialog", () => {
  test("with both, all three in-browser options are offered", async () => {
    await mount();
    expect(screen.getByText("ASR (in this browser)")).toBeTruthy();
    expect(screen.getByText("Segments from sound level")).toBeTruthy();
    expect(screen.getByText("ASR into empty segments (in this browser)")).toBeTruthy();
  });

  test("a browser that cannot run a model loses the two ASR options, not sound level", async () => {
    state.engine = false;
    await mount();
    expect(screen.queryByText("ASR (in this browser)")).toBeNull();
    expect(screen.queryByText("ASR into empty segments (in this browser)")).toBeNull();
    expect(screen.getByText("Segments from sound level")).toBeTruthy();
  });

  test("a browser that cannot decode audio loses sound level, not the ASR", async () => {
    state.energy = false;
    await mount();
    expect(screen.queryByText("Segments from sound level")).toBeNull();
    expect(screen.getByText("ASR (in this browser)")).toBeTruthy();
  });

  test("sound level alone is enough to make a menu rather than a notice", async () => {
    state.engine = false;
    await mount();
    expect(screen.getByText("Segments from sound level")).toBeTruthy();
    expect(screen.queryByText(/Nothing this menu offers can run/)).toBeNull();
  });

  test("with neither, a notice says so and nothing is offered", async () => {
    state.engine = false;
    state.energy = false;
    await mount();
    expect(screen.queryByText("ASR (in this browser)")).toBeNull();
    expect(screen.queryByText("Segments from sound level")).toBeNull();
    expect(screen.getByText(/Nothing this menu offers can run in this browser/)).toBeTruthy();
  });

  // The invariant: this app ships no hosted-service entries. Not hidden behind
  // a configuration check -- absent, in every state the dialog can be in.
  test("the hosted services are never offered, whatever the browser can do", async () => {
    for (const [engine, energy] of [[true, true], [true, false], [false, true], [false, false]]) {
      state.engine = engine;
      state.energy = energy;
      const { unmount } = await mount();
      for (const name of ["SAD", "ASR", "ASR (Korean)", "ASR (Rev.ai)"]) {
        expect(screen.queryByText(name)).toBeNull();
      }
      unmount();
    }
  });
});
