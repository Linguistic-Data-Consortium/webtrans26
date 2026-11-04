import { describe, expect, test } from "vitest";
import { window_count, count_windows, pipeline_options, SINGLE_PASS_MAX_NEW_TOKENS } from "./asr_windows";

// The pipeline's own loop: 30 s windows starting 20 s apart until one
// reaches the end. "part 2 of 5" is only true if this matches it.
describe("window_count", () => {
  const s = (seconds: number) => seconds * 16000;
  test("up to 30 s is one window", () => {
    expect(window_count(s(10))).toBe(1);
    expect(window_count(s(30))).toBe(1);
  });
  test("then one more every 20 s", () => {
    expect(window_count(s(31))).toBe(2);
    expect(window_count(s(50))).toBe(2);
    expect(window_count(s(51))).toBe(3);
    expect(window_count(s(100))).toBe(5);
  });
  test("follows other window and stride lengths", () => {
    expect(window_count(s(100), { chunk_length_s: 20, stride_length_s: 2 })).toBe(6);
  });
});

describe("count_windows", () => {
  // Like Whisper's: generate makes passes of its own (the seek loop), each of
  // which would end a streamer; the pipeline calls generate once a window.
  function whisper_like() {
    const m: any = { passes: 0 };
    m.pass = async () => { m.passes++; };
    m.generate = async function (this: any, args: any) { await this.pass(); await this.pass(); return args; };
    return m;
  }

  test("once per window, however many passes each makes", async () => {
    const m = whisper_like();
    let windows = 0;
    count_windows(m, () => windows++);
    for (let w = 0; w < 5; w++) expect(await m.generate(w)).toBe(w);
    expect(windows).toBe(5);
    expect(m.passes).toBe(10);
  });

  test("wrapped once, whatever reuses the model", async () => {
    const m = whisper_like();
    let windows = 0;
    count_windows(m, () => windows++);
    count_windows(m, () => windows += 100);
    await m.generate(1);
    expect(windows).toBe(1);
  });
});

describe("pipeline_options", () => {
  test("30 s windows, 5 s overlaps, timestamps, and the seek loop left alone", () => {
    expect(pipeline_options()).toEqual({ chunk_length_s: 30, stride_length_s: 5, return_timestamps: true });
  });
  // max_new_tokens is what makes transformers.js skip the seek loop.
  test("one pass per window sets max_new_tokens, within Whisper's 448", () => {
    expect(pipeline_options({ single_pass: true }).max_new_tokens).toBe(SINGLE_PASS_MAX_NEW_TOKENS);
    expect(SINGLE_PASS_MAX_NEW_TOKENS).toBeLessThan(448);
  });
  test("without timestamps there's no seek loop to skip", () => {
    expect(pipeline_options({ timestamps: false, single_pass: true })).toEqual({ chunk_length_s: 30, stride_length_s: 5, return_timestamps: false });
  });
});

describe("pipeline_options and language", () => {
  // The library can't detect a language: a multilingual model is told it.
  test("a language goes with the task to transcribe", () => {
    expect(pipeline_options({ language: "fr" })).toMatchObject({ language: "fr", task: "transcribe" });
  });
  test("none, for an English-only model, which would refuse one", () => {
    expect(pipeline_options({ language: null })).not.toHaveProperty("language");
  });
});

