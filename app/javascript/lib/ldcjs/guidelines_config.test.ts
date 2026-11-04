import { describe, expect, test, beforeEach, afterEach } from "vitest";
import { guidelines_url, guidelines_configured } from "./service_config";

// webtrans26 ships no guidelines document: the public release must not point at
// somebody else's. The help dialog reports that instead of opening a window.
describe("the annotation guidelines document is configuration", () => {
  afterEach(() => document.querySelectorAll('meta[name="guidelines-url"]').forEach(m => m.remove()));

  const set = (v: string) => {
    const m = document.createElement("meta");
    m.name = "guidelines-url"; m.content = v;
    document.head.appendChild(m);
  };

  test("unconfigured, there is no url and nothing to open", () => {
    expect(guidelines_url()).toBe("");
    expect(guidelines_configured()).toBe(false);
  });

  test("an empty tag is the same as no tag", () => {
    set("");
    expect(guidelines_configured()).toBe(false);
  });

  test("the server's value is what gets opened", () => {
    set("https://example.org/our-guidelines");
    expect(guidelines_url()).toBe("https://example.org/our-guidelines");
    expect(guidelines_configured()).toBe(true);
  });
});
