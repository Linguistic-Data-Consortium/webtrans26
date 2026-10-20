import { render, screen } from "@testing-library/svelte";
import { tick } from "svelte";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import AudioPlayer from "./audio_player.svelte";

describe("audio_player.svelte", () => {
  let originalCreateObjectURL: typeof URL.createObjectURL;

  beforeEach(() => {
    originalCreateObjectURL = URL.createObjectURL;
    URL.createObjectURL = vi.fn(() => "blob:mocked-url");
  });

  afterEach(() => {
    URL.createObjectURL = originalCreateObjectURL;
  });

  test("renders an audio element with controls enabled after mount", async () => {
    const { container } = render(AudioPlayer, { url: "https://example.com/audio.mp3", filename: "audio.mp3" });
    await tick();
    const audio = container.querySelector("audio") as HTMLAudioElement;
    expect(audio).not.toBeNull();
    expect(audio.controls).toBe(true);
  });

  test("sets src from url prop when no blob is provided", async () => {
    const { container } = render(AudioPlayer, { url: "https://example.com/audio.mp3", filename: "audio.mp3" });
    await tick();
    const audio = container.querySelector("audio") as HTMLAudioElement;
    expect(audio.getAttribute("src")).toBe("https://example.com/audio.mp3");
  });

  test("sets src from createObjectURL when blob is provided", async () => {
    const blob = new Blob(["fake audio"], { type: "audio/mpeg" });
    const { container } = render(AudioPlayer, { blob, filename: "recorded.mp3" });
    await tick();
    const audio = container.querySelector("audio") as HTMLAudioElement;
    expect(URL.createObjectURL).toHaveBeenCalledWith(blob);
    expect(audio.getAttribute("src")).toBe("blob:mocked-url");
  });

  test("renders a download link pointing at the audio source", async () => {
    render(AudioPlayer, { url: "https://example.com/audio.mp3", filename: "track.mp3" });
    await tick();
    const link = screen.getByRole("link", { name: "download" }) as HTMLAnchorElement;
    expect(link).toBeInTheDocument();
    expect(link.getAttribute("href")).toBe("https://example.com/audio.mp3");
    expect(link.getAttribute("download")).toBe("track.mp3");
  });
});
