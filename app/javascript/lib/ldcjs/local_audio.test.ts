import { afterEach, describe, expect, test } from "vitest";
import {
  is_local_docid, local_docid, local_name, register_local_file, local_file_for,
  local_audio_active, local_file_mismatch, forget_local_files
} from "./local_audio";
import { getp_wav } from "./getp";

// A local_audio kit's audio is a File the annotator picked. It stands in for
// the S3 url under a blob: url, and getp_wav reads ranges off the File itself.
function wav_file(name: string, n: number) {
  const bytes = new Uint8Array(n);
  for (let i = 0; i < n; i++) bytes[i] = i % 256;
  return new File([ bytes ], name, { type: "audio/wav" });
}

afterEach(() => forget_local_files());

describe("docids", () => {
  test("local:// names a kit's local file", () => {
    expect(local_docid("a b.wav")).toBe("local://a b.wav");
    expect(is_local_docid("local://a b.wav")).toBe(true);
    expect(local_name("local://a b.wav")).toBe("a b.wav");
  });

  test("other sources aren't local", () => {
    expect(is_local_docid("s3://bucket/a.wav")).toBe(false);
    expect(is_local_docid("https://example.com/a.wav")).toBe(false);
    expect(is_local_docid(undefined)).toBe(false);
  });
});

describe("registering a file", () => {
  test("gives a blob url that maps back to the file, and turns the services off", () => {
    expect(local_audio_active()).toBe(false);
    const file = wav_file("a.wav", 16);
    const url = register_local_file(file);
    expect(url).toMatch(/^blob:/);
    expect(local_file_for(url)).toBe(file);
    expect(local_audio_active()).toBe(true);
  });
});

describe("getp_wav", () => {
  // Inclusive at both ends, as a Range header counts.
  test("reads exactly the range asked for off the file", async () => {
    const url = register_local_file(wav_file("a.wav", 1000));
    const data = new Uint8Array(await getp_wav(url, 10, 19));
    expect(data.length).toBe(10);
    expect(Array.from(data)).toEqual([ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 ]);
  });

  test("a range running past the end stops at the end, as a server's would", async () => {
    const url = register_local_file(wav_file("a.wav", 100));
    const data = new Uint8Array(await getp_wav(url, 0, 8191));
    expect(data.length).toBe(100);
  });
});

describe("checking a re-picked file", () => {
  test("the same name and size is accepted", () => {
    expect(local_file_mismatch(wav_file("a.wav", 50), "a.wav", 50)).toBeNull();
  });

  test("no recorded size checks the name only", () => {
    expect(local_file_mismatch(wav_file("a.wav", 50), "a.wav", null)).toBeNull();
  });

  test("a different name is refused", () => {
    expect(local_file_mismatch(wav_file("b.wav", 50), "a.wav", 50)).toMatch(/a\.wav, not b\.wav/);
  });

  test("the same name at a different size is refused", () => {
    expect(local_file_mismatch(wav_file("a.wav", 51), "a.wav", 50)).toMatch(/51 bytes.*50 bytes/);
  });
});
