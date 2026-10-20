import { beforeEach, describe, expect, test, vi } from "vitest";

// /token asks the server for Cognito credentials. It used to be requested when
// this module was imported, so every page that pulled it in asked — whether or
// not it went on to touch S3. On an instance with no Cognito configured that is
// a failing request and a console error on every load, for a capability the page
// was never going to use.
//
// Nothing here asserts the AWS calls themselves; the point is only *when* the
// token is fetched.
const fetchMock = vi.fn(() =>
  Promise.resolve({ json: () => Promise.resolve({ tok: {}, region: "us-east-1" }) }),
);
vi.stubGlobal("fetch", fetchMock);

vi.mock("@aws-sdk/client-s3", () => ({ GetObjectCommand: class {}, ListObjectsV2Command: class {} }));

const sdk = {
  CognitoIdentityClient: class {},
  fromCognitoIdentity: () => ({}),
  S3Client: class {},
  GetObjectCommand: class {},
  getSignedUrl: () => Promise.resolve("https://signed"),
};

import { refreshToken, gets3 } from "./aws_helper";

// These tests are about *when* a configured instance asks for its token, so
// they have to say the instance is configured. Without the meta tag the layout
// renders, s3_configured() is false and client() refuses before fetching —
// which is the subject of the second describe below.
function set_s3_available(v: string) {
  document.head.querySelectorAll('meta[name="s3-available"]').forEach((el) => el.remove());
  const el = document.createElement("meta");
  el.setAttribute("name", "s3-available");
  el.setAttribute("content", v);
  document.head.appendChild(el);
}

describe("the Cognito token is fetched when it is needed, not when imported", () => {
  beforeEach(() => { fetchMock.mockClear(); set_s3_available("true"); });

  test("importing the module asks for nothing", () => {
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("registering the SDK classes asks for nothing either", () => {
    refreshToken(sdk);

    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("the first real use is what asks", async () => {
    refreshToken(sdk);
    await gets3();

    expect(fetchMock).toHaveBeenCalledWith("/token", { method: "POST" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  test("and it is asked once, however many uses follow", async () => {
    refreshToken(sdk);
    await Promise.all([ gets3(), gets3(), gets3() ]);

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  // What the name promises: a later call drops the cached client, so an
  // expired-credentials retry gets a fresh token.
  test("registering again drops the cached client", async () => {
    refreshToken(sdk);
    await gets3();
    expect(fetchMock).toHaveBeenCalledTimes(1);

    refreshToken(sdk);
    await gets3();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});

// Most installs will never configure Cognito, and the browser reaches S3 only
// through POST /token. It used to ask anyway: the request failed, the .catch
// logged it and resolved to undefined, and every caller then threw "cannot read
// properties of undefined" with nothing naming the cause.
describe("with no Cognito configured", () => {
  beforeEach(() => { fetchMock.mockClear(); set_s3_available("false"); });

  test("nothing is asked of the server", async () => {
    refreshToken(sdk);
    await gets3().catch(() => {});

    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("the caller gets an error it can show, not undefined", async () => {
    refreshToken(sdk);

    await expect(gets3()).rejects.toThrow(/not configured/i);
  });

  // The safe direction: an absent tag must read as unavailable, not available.
  test("an absent tag is treated as unconfigured", async () => {
    document.head.querySelectorAll('meta[name="s3-available"]').forEach((el) => el.remove());
    refreshToken(sdk);

    await expect(gets3()).rejects.toThrow(/not configured/i);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
