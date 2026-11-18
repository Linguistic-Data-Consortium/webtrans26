import { describe, expect, test, vi, beforeEach } from "vitest";
import { readFileSync, readdirSync, statSync } from "fs";
import path from "path";

// The one rule for turning a kit's s3:// source into a bucket and a key —
// lib/ldcjs/s3_source.js, aws/s3_project_prefixes.md.

const cognito = vi.hoisted(() => ({
  getSignedUrlPromise: vi.fn((b: string, k: string) => Promise.resolve(`cognito:${b}:${k}`)),
  headObject: vi.fn(() => Promise.resolve({})),
}));
const session = vi.hoisted(() => ({
  signed_url: vi.fn((b: string, k: string) => Promise.resolve(`session:${b}:${k}`)),
  head_object: vi.fn(() => Promise.resolve({})),
}));
vi.mock("./aws_helper", async (orig) => {
  const real: any = await orig();
  return { s3url: real.s3url, getSignedUrlPromise: cognito.getSignedUrlPromise, headObject: cognito.headObject };
});
vi.mock("./s3_session", () => session);

import { s3url } from "./aws_helper";
import { resolve_s3_source, entry_source, resolve_audio, set_s3_project, signed_url_for } from "./s3_source";

const on = { bucket: "the-bucket", project_id: 7 };

beforeEach(() => {
  set_s3_project(null);
  cognito.getSignedUrlPromise.mockClear();
  session.signed_url.mockClear();
});

describe("the rule on: everything after s3:// is a path under the project", () => {
  test("s3://foo — no slash, which the old parser drops", () => {
    expect(s3url("s3://foo")).toEqual({});
    expect(resolve_s3_source("s3://foo", on)).toEqual({ bucket: "the-bucket", key: "7/foo" });
  });

  test("s3://foo/bar/take1.wav", () => {
    expect(resolve_s3_source("s3://foo/bar/take1.wav", on))
      .toEqual({ bucket: "the-bucket", key: "7/foo/bar/take1.wav" });
  });

  test("a source that names a bucket is reinterpreted, not honoured", () => {
    expect(resolve_s3_source("s3://my-bucket/recordings/x.wav", on))
      .toEqual({ bucket: "the-bucket", key: "7/my-bucket/recordings/x.wav" });
  });

  test("a kit with no project resolves nothing, rather than the bucket root", () => {
    expect(resolve_s3_source("s3://foo", { bucket: "the-bucket", project_id: null })).toEqual({});
    expect(resolve_s3_source("s3://foo", { bucket: "the-bucket", project_id: undefined })).toEqual({});
  });

  test("a project id that isn't an integer resolves nothing", () => {
    expect(resolve_s3_source("s3://foo", { bucket: "the-bucket", project_id: "7/../9" })).toEqual({});
  });

  test("http urls and paths are not s3 sources", () => {
    expect(resolve_s3_source("https://example.org/a.wav", on)).toEqual({});
    expect(resolve_s3_source("/test_tone_10s.wav", on)).toEqual({});
  });

  test("signing goes through the per-project session, never Cognito", async () => {
    await expect(signed_url_for("s3://foo/a.wav", on)).resolves.toBe("session:the-bucket:7/foo/a.wav");
    expect(cognito.getSignedUrlPromise).not.toHaveBeenCalled();
  });
});

describe("the rule off: exactly what s3url() gave before", () => {
  const sources = ["s3://my-bucket/recordings/x.wav", "s3://foo", "s3://b/k/with/slashes.json", "https://x/a.wav", "s3", ""];
  for (const src of sources) {
    test(JSON.stringify(src), () => {
      expect(resolve_s3_source(src, null)).toEqual(s3url(src));
    });
  }

  test("a source naming a bucket resolves to that bucket", () => {
    expect(resolve_s3_source("s3://my-bucket/recordings/x.wav"))
      .toEqual({ bucket: "my-bucket", key: "recordings/x.wav" });
  });

  test("signing goes through Cognito, as it always has", async () => {
    await expect(signed_url_for("s3://my-bucket/x.wav")).resolves.toBe("cognito:my-bucket:x.wav");
    expect(session.signed_url).not.toHaveBeenCalled();
  });
});

describe("one manifest entry, one answer, whichever string a site starts from", () => {
  test("the entry's own name wins when it is a source", () => {
    expect(entry_source("s3://b/k.wav", { "s3://b/k.wav": "s3://b/k.wav" }, null)).toBe("s3://b/k.wav");
  });

  test("otherwise the manifest's value for it", () => {
    expect(entry_source("doc1", { doc1: "s3://b/k.wav" }, null)).toBe("s3://b/k.wav");
  });

  test("neither: not an s3 entry", () => {
    expect(entry_source("doc1", { doc1: "https://x/a.wav" }, null)).toBeNull();
  });

  test("resolve_audio signs an s3 entry and records the url", async () => {
    set_s3_project(on);
    const urls: Record<string, string> = { "s3://foo": "s3://foo" };
    await expect(resolve_audio("s3://foo", urls)).resolves.toEqual({ wav: "s3://foo", wav_url: "session:the-bucket:7/foo" });
    expect(urls["s3://foo"]).toBe("session:the-bucket:7/foo");
  });

  test("resolve_audio passes an http url through", async () => {
    const urls: Record<string, string> = {};
    await expect(resolve_audio("https://x/a.wav", urls)).resolves.toEqual({ wav: "https://x/a.wav", wav_url: "https://x/a.wav" });
  });

  test("resolve_audio passes a path through", async () => {
    const urls = { doc: "/a.wav" };
    await expect(resolve_audio("doc", urls)).resolves.toEqual({ wav: "doc", wav_url: "/a.wav" });
  });

  test("resolve_audio with nothing to go on returns undefined, as the copies it replaced did", () => {
    expect(resolve_audio("doc", {})).toBeUndefined();
  });

  test("resolve_audio alerts on an s3 value it can't resolve", () => {
    const alert = vi.spyOn(window, "alert").mockImplementation(() => {});
    expect(resolve_audio("doc", { doc: "s3" })).toBeUndefined();
    expect(alert).toHaveBeenCalledOnce();
    alert.mockRestore();
  });
});

// The failure this guards against is not a wrong answer but another copy: the
// three pasted blocks were identical, and a fourth would be too.
describe("one derivation, not five", () => {
  const root = path.resolve("app/javascript");
  function files(dir: string): string[] {
    return readdirSync(dir).flatMap((f) => {
      const p = path.join(dir, f);
      if (statSync(p).isDirectory()) return files(p);
      return /\.(js|ts|svelte)$/.test(p) && !/\.test\.ts$/.test(p) ? [p] : [];
    });
  }
  const sources = files(root).map((p) => [path.relative(root, p), readFileSync(p, "utf8")] as const);

  test("the hand-rolled bucket-from-one-string, key-from-another block appears nowhere", () => {
    const hits = sources.filter(([, src]) => src.includes("urls[k].replace(/^s3(:\\/\\/)?/, '')")).map(([f]) => f);
    expect(hits).toEqual([]);
  });

  test("the s3:// bucket/key regex is defined once, in aws_helper.js", () => {
    const hits = sources.filter(([, src]) => src.includes("/^s3:\\/\\/([^\\/]+)\\/(.+)/")).map(([f]) => f);
    expect(hits).toEqual(["lib/ldcjs/aws_helper.js"]);
  });

  test("nothing writes ldc.resources.bucket as a side effect any more", () => {
    const hits = sources.filter(([, src]) => /resources\.bucket\s*=[^=]/.test(src)).map(([f]) => f);
    expect(hits).toEqual([]);
  });
});
