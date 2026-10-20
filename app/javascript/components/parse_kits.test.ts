import { describe, expect, test } from "vitest";
import { looks_like_json, parse_kits } from "./parse_kits";

describe("parse_kits", () => {
  test("a bare line is a docid", () => {
    expect(parse_kits("foo.wav\nbar.wav")).toEqual([
      { docid: "foo.wav" },
      { docid: "bar.wav" },
    ]);
  });

  test("a field after the docid gives the kit an owner", () => {
    expect(parse_kits("foo.wav user_id=alice")).toEqual([
      { docid: "foo.wav", user_id: "alice" },
    ]);
  });

  test("the owner may be written however the person typing has it", () => {
    expect(parse_kits("a.wav user_id=7\nb.wav user_id=alice\nc.wav user_id=alice@example.org")).toEqual([
      { docid: "a.wav", user_id: "7" },
      { docid: "b.wav", user_id: "alice" },
      { docid: "c.wav", user_id: "alice@example.org" },
    ]);
  });

  test("owned and unowned lines mix", () => {
    expect(parse_kits("a.wav\nb.wav user_id=bob")).toEqual([
      { docid: "a.wav" },
      { docid: "b.wav", user_id: "bob" },
    ]);
  });

  test("blank lines and stray whitespace are not kits", () => {
    expect(parse_kits("\n  a.wav   user_id=bob  \n\n   \n")).toEqual([
      { docid: "a.wav", user_id: "bob" },
    ]);
  });

  test("an s3 url is a docid like any other", () => {
    expect(parse_kits("s3://bucket/REC_passage.wav user_id=bob")).toEqual([
      { docid: "s3://bucket/REC_passage.wav", user_id: "bob" },
    ]);
  });

  // A typo shouldn't quietly make fewer kits than were asked for, so the line
  // comes back carrying its complaint and the dialog refuses to submit.
  test("a field that isn't one says so", () => {
    const [ kit ] = parse_kits("foo.wav owner=alice");
    expect(kit.docid).toBe("foo.wav");
    expect(kit.error).toMatch(/owner: not a field/);
    expect(kit.owner).toBeUndefined();
  });

  test("a bare word after the docid says so", () => {
    expect(parse_kits("foo.wav alice")[0].error).toMatch(/alice: expected key=value/);
  });

  test("a field with no value says so", () => {
    expect(parse_kits("foo.wav user_id=")[0].error).toMatch(/user_id: no value/);
  });

  test("nothing at all is no kits", () => {
    expect(parse_kits("")).toEqual([]);
    expect(parse_kits(null as never)).toEqual([]);
  });
});

// The file dialog asks this to decide how to read what was uploaded. It used
// to ask whether the first line had a space in it, which a line naming an
// owner does — those files fell through to "unknown format" with nothing to
// press.
describe("looks_like_json", () => {
  test("a kit list is not json, whatever its lines look like", () => {
    expect(looks_like_json("foo.wav")).toBe(false);
    expect(looks_like_json("foo.wav user_id=alice")).toBe(false);
    expect(looks_like_json("foo.wav user_id=alice\nbar.wav")).toBe(false);
    expect(looks_like_json("s3://bucket/a.wav user_id=alice@example.org")).toBe(false);
  });

  test("json is json, leading whitespace and all", () => {
    expect(looks_like_json('[{"docid":"foo.wav"}]')).toBe(true);
    expect(looks_like_json('\n  [{"docid":"foo.wav"}]')).toBe(true);
    expect(looks_like_json('{"docid":"foo.wav"}')).toBe(true);
  });

  test("nothing is not json", () => {
    expect(looks_like_json("")).toBe(false);
    expect(looks_like_json("   \n ")).toBe(false);
    expect(looks_like_json(null as never)).toBe(false);
  });
});
