import { describe, expect, test } from "vitest";
import { display_point_count } from "./display_points";

// The zoomed-in drawing mode plots one point per sample. A decoded buffer can
// cover far more audio than the window it ends up being drawn against — a fetch
// stays in flight while the window moves, which following the active segment
// does constantly — and plotting all of it threw "RangeError: Invalid array
// length" once the point array passed 2^32-1 entries.
describe("display_point_count", () => {
  test("plots the whole buffer when it fits the window", () => {
    // 1000 px at 4 samples/px = 4000 visible samples; the buffer holds 3000.
    expect(display_point_count(3000, 1000, 4)).toBe(3000);
  });

  test("stops at what the canvas can show when the buffer is longer", () => {
    expect(display_point_count(10_000_000, 1000, 4)).toBe(4001);
  });

  test("a huge buffer with a zoomed-in window stays bounded", () => {
    // The crash: ~13 hours of audio at 44.1kHz paired with sub-pixel zoom.
    const count = display_point_count(2_100_000_000, 1400, 0.5);
    expect(count).toBe(701);
    expect(count * 2).toBeLessThan(2 ** 32 - 1);
  });

  test("sub-pixel zoom still yields at least the visible samples", () => {
    expect(display_point_count(50_000, 800, 0.25)).toBe(201);
  });

  test("nothing to plot for an empty or nonsensical buffer", () => {
    expect(display_point_count(0, 1000, 4)).toBe(0);
    expect(display_point_count(-1, 1000, 4)).toBe(0);
    expect(display_point_count(NaN, 1000, 4)).toBe(0);
    expect(display_point_count(undefined as any, 1000, 4)).toBe(0);
  });

  // samples_per_pixel is a division, so it can arrive as NaN or Infinity before
  // the audio's sample rate is known.
  test("nothing to plot when the window measurements are unusable", () => {
    expect(display_point_count(1000, 1000, NaN)).toBe(0);
    expect(display_point_count(1000, 1000, Infinity)).toBe(0);
    expect(display_point_count(1000, 1000, 0)).toBe(0);
    expect(display_point_count(1000, 1000, -4)).toBe(0);
    expect(display_point_count(1000, NaN, 4)).toBe(0);
    expect(display_point_count(1000, 0, 4)).toBe(0);
  });

  test("a fractional buffer length is floored", () => {
    expect(display_point_count(10.9, 1000, 4)).toBe(10);
  });
});
