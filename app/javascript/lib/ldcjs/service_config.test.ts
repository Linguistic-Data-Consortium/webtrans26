import { afterEach, describe, expect, test } from "vitest";
import { hlt_endpoint, promise_bucket, services_configured } from "./service_config";

// The SAD/ASR endpoint and its bucket come from meta tags the layout renders.
//
// This app is the public release, so unlike wta both default to **empty**: an
// instance that has configured nothing must not fall back to LDC's own service
// and send a stranger's audio to a host they have never heard of. The feature is
// unavailable until the server sets HLT_ENDPOINT and PROMISE_BUCKET.
function set_meta(name: string, content: string) {
  const el = document.createElement("meta");
  el.setAttribute("name", name);
  el.setAttribute("content", content);
  document.head.appendChild(el);
}

afterEach(() => {
  document.head.querySelectorAll('meta[name="hlt-endpoint"], meta[name="promise-bucket"]')
    .forEach((el) => el.remove());
});

describe("unconfigured means unconfigured, not LDC", () => {
  test("no meta tag at all", () => {
    expect(hlt_endpoint()).toBe("");
    expect(promise_bucket()).toBe("");
  });

  test("a present but empty tag", () => {
    set_meta("hlt-endpoint", "");
    set_meta("promise-bucket", "");

    expect(hlt_endpoint()).toBe("");
    expect(promise_bucket()).toBe("");
  });

  // The guard that matters: no default may name a real host or bucket.
  test("no default names anything outside this instance", () => {
    expect(hlt_endpoint()).not.toMatch(/ldcresearch|upenn/);
    expect(promise_bucket()).not.toMatch(/promise-uploads|coghealth/);
  });
});

describe("reads what the layout rendered", () => {
  test("both values", () => {
    set_meta("hlt-endpoint", "https://sad.example.org");
    set_meta("promise-bucket", "my-promises");

    expect(hlt_endpoint()).toBe("https://sad.example.org");
    expect(promise_bucket()).toBe("my-promises");
  });

  // Read on every call, not captured at import: some entry points load before
  // the document is parsed, and a captured value would stick for the session.
  test("a tag added after import is still picked up", () => {
    expect(promise_bucket()).toBe("");

    set_meta("promise-bucket", "later");

    expect(promise_bucket()).toBe("later");
  });
});

// Many installs will never set HLT_ENDPOINT or PROMISE_BUCKET. Callers use this
// to stay out of the way — the Services dialog shows a notice instead of a
// numbered menu, run_sad/run_asr4 set status 'unavailable' instead of posting to
// an empty URL, and the Open Promises button is hidden. So the predicate has to
// be false unless *both* halves are present: an endpoint with no bucket has
// nowhere to put the audio, and a bucket with no endpoint has nothing to ask.
describe("services_configured", () => {
  test("false when nothing is set — the common case", () => {
    expect(services_configured()).toBe(false);
  });

  test("false with only an endpoint", () => {
    set_meta("hlt-endpoint", "https://sad.example.org");

    expect(services_configured()).toBe(false);
  });

  test("false with only a bucket", () => {
    set_meta("promise-bucket", "my-promises");

    expect(services_configured()).toBe(false);
  });

  test("true only with both", () => {
    set_meta("hlt-endpoint", "https://sad.example.org");
    set_meta("promise-bucket", "my-promises");

    expect(services_configured()).toBe(true);
  });
});
