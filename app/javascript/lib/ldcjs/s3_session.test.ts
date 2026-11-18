import { beforeEach, describe, expect, test, vi } from "vitest";

// POST /s3_session, the client half: fetched on demand, held in memory, fetched
// again near expiry, and refused outright when the server says it is off.

const sent: any[] = [];
vi.mock("@aws-sdk/client-s3", () => ({
  S3Client: class { config: any; constructor(c: any) { this.config = c; } send(cmd: any) { sent.push(cmd); return Promise.resolve({ ok: true }); } },
  GetObjectCommand: class { constructor(public input: any) {} },
  HeadObjectCommand: class { constructor(public input: any) {} },
  ListObjectsV2Command: class { constructor(public input: any) {} },
  PutObjectCommand: class { constructor(public input: any) {} },
}));
vi.mock("@aws-sdk/s3-request-presigner", () => ({
  getSignedUrl: (_c: any, cmd: any) => Promise.resolve(`signed:${cmd.input.Bucket}/${cmd.input.Key}`),
}));

function body(expires_at: string) {
  return {
    credentials: { access_key_id: "AK", secret_access_key: "SK", session_token: "ST" },
    region: "us-east-1", bucket: "the-bucket", expires_at,
  };
}
const later = () => new Date(Date.now() + 3600_000).toISOString();
const fetchMock = vi.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve(body(later())) }));
vi.stubGlobal("fetch", fetchMock);

import { get_session, signed_url, head_object, _reset } from "./s3_session";

function set_meta(name: string, v: string) {
  document.head.querySelectorAll(`meta[name="${name}"]`).forEach((el) => el.remove());
  const el = document.createElement("meta");
  el.setAttribute("name", name);
  el.setAttribute("content", v);
  document.head.appendChild(el);
}

beforeEach(() => {
  _reset();
  fetchMock.mockClear();
  sent.length = 0;
  set_meta("s3-sessions-available", "true");
  set_meta("s3-available", "false");
});

describe("when it asks", () => {
  test("importing asks for nothing", () => {
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("the first use asks, once, and later uses reuse it", async () => {
    await signed_url("the-bucket", "7/a.wav");
    await head_object("the-bucket", "7/a.wav");
    await signed_url("the-bucket", "7/b.wav");

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0][0]).toBe("/s3_session");
    expect((fetchMock.mock.calls[0] as any)[1].method).toBe("POST");
  });

  test("concurrent first uses share one request", async () => {
    await Promise.all([get_session(), get_session(), get_session()]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  test("near expiry it asks again", async () => {
    fetchMock.mockImplementationOnce(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve(body(new Date(Date.now() + 30_000).toISOString())) }));
    await get_session();
    await get_session();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});

describe("what it holds", () => {
  test("the server's credentials, in the SDK's shape, and nowhere persistent", async () => {
    const s = await get_session();
    expect(s.credentials).toMatchObject({ accessKeyId: "AK", secretAccessKey: "SK", sessionToken: "ST" });
    expect(s.bucket).toBe("the-bucket");
    expect(JSON.stringify(localStorage)).not.toContain("SK");
    expect(JSON.stringify(sessionStorage)).not.toContain("SK");
  });

  test("signs with what it was given", async () => {
    await expect(signed_url("the-bucket", "7/a.wav")).resolves.toBe("signed:the-bucket/7/a.wav");
  });
});

describe("when it refuses", () => {
  test("off, it asks nothing and says why — whatever s3-available says", async () => {
    set_meta("s3-sessions-available", "false");
    set_meta("s3-available", "true");
    await expect(get_session()).rejects.toThrow("Per-project S3 is not configured on this server");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("with no tag at all it is off", async () => {
    document.head.querySelectorAll('meta[name="s3-sessions-available"]').forEach((el) => el.remove());
    await expect(get_session()).rejects.toThrow();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("a 403 rejects with the server's own message, and the next call tries again", async () => {
    fetchMock.mockImplementationOnce(() =>
      Promise.resolve({ ok: false, status: 403, json: () => Promise.resolve({ error: "You are not a member of any project" }) }));
    await expect(get_session()).rejects.toThrow("You are not a member of any project");
    await get_session();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
