import { describe, expect, test } from "vitest";
import parse from "./parse_tsv";

// The wrapper/auto-import path (import_transcript_blanks and friends) reads TSV
// through this parser. Two header styles are accepted — the original "Kit"
// style and the "file  beg  end  text" style — and either may stop after the
// text column, omitting speaker and section.
const rows = (text: string) => parse(text).map(({ beg, end, text: t, speaker, section }) =>
  ({ beg, end, text: t, speaker, section }));

describe("parse_tsv — Kit header style", () => {
  test("skips the header and reads beg/end/text/speaker/section", () => {
    const tsv = [
      "Kit\tSource\tBegin\tEnd\tText\tSpeaker\tSection",
      "1\tCarrieFisher10s\t0.56\t4.599\tThat's Carrie Fisher\thost\tintro",
      "2\tCarrieFisher10s\t4.76\t6.55\tin the first Star Wars film.\tguest\tbody",
    ].join("\n");
    expect(rows(tsv)).toEqual([
      { beg: 0.56, end: 4.599, text: "That's Carrie Fisher", speaker: "host", section: "intro" },
      { beg: 4.76, end: 6.55, text: "in the first Star Wars film.", speaker: "guest", section: "body" },
    ]);
  });

  test("speaker and section may be omitted", () => {
    const tsv = [
      "Kit\tSource\tBegin\tEnd\tText",
      "1\tsrc\t0.5\t1.25\thello",
    ].join("\n");
    expect(rows(tsv)).toEqual([{ beg: 0.5, end: 1.25, text: "hello", speaker: "", section: "" }]);
  });

  test("still parses without a header", () => {
    expect(rows("1\tsrc\t0.5\t1.25\thello")).toEqual([
      { beg: 0.5, end: 1.25, text: "hello", speaker: "", section: "" },
    ]);
  });
});

describe("parse_tsv — file header style", () => {
  test("reads file\\tbeg\\tend\\ttext\\tspeaker\\tsection", () => {
    const tsv = [
      "file\tbeg\tend\ttext\tspeaker\tsection",
      "lecture.wav\t0.0\t2.0\tintroduction\tprof\tintro",
      "lecture.wav\t2.0\t5.0\tmain topic\tprof\tbody",
    ].join("\n");
    expect(rows(tsv)).toEqual([
      { beg: 0, end: 2, text: "introduction", speaker: "prof", section: "intro" },
      { beg: 2, end: 5, text: "main topic", speaker: "prof", section: "body" },
    ]);
  });

  test("section may be omitted", () => {
    const tsv = [
      "file\tbeg\tend\ttext\tspeaker",
      "interview.wav\t0.0\t1.5\thello there\tspk1",
    ].join("\n");
    expect(rows(tsv)).toEqual([{ beg: 0, end: 1.5, text: "hello there", speaker: "spk1", section: "" }]);
  });

  test("speaker and section may both be omitted", () => {
    const tsv = ["file\tbeg\tend\ttext", "hamlet.wav\t1.1\t2.2\tto be"].join("\n");
    expect(rows(tsv)).toEqual([{ beg: 1.1, end: 2.2, text: "to be", speaker: "", section: "" }]);
  });

  test("a row whose file name starts with 'file' is data, not a header", () => {
    const tsv = ["file\tbeg\tend\ttext", "file_003.wav\t1.0\t2.0\thello"].join("\n");
    expect(rows(tsv)).toEqual([{ beg: 1, end: 2, text: "hello", speaker: "", section: "" }]);
  });

  test("still parses without a header (times in columns 1 and 2)", () => {
    expect(rows("hamlet.wav\t1.1\t2.2\tto be")).toEqual([
      { beg: 1.1, end: 2.2, text: "to be", speaker: "", section: "" },
    ]);
  });
});

describe("parse_tsv — general", () => {
  test("sorts by begin time and rounds to 3 places", () => {
    const tsv = [
      "file\tbeg\tend\ttext",
      "a.wav\t5.0\t6.0\tsecond",
      "a.wav\t1.00049\t2.0\tfirst",
    ].join("\n");
    expect(parse(tsv).map((x) => [x.beg, x.text])).toEqual([[1.0, "first"], [5.0, "second"]]);
  });

  test("ignores blank lines, trailing newline and CRLF line endings", () => {
    const tsv = "file\tbeg\tend\ttext\r\na.wav\t1.0\t2.0\thello\r\n\r\n";
    expect(rows(tsv)).toEqual([{ beg: 1, end: 2, text: "hello", speaker: "", section: "" }]);
  });

  test("drops rows without numeric times", () => {
    const tsv = ["file\tbeg\tend\ttext", "a.wav\tx\ty\tjunk", "a.wav\t1.0\t2.0\tgood"].join("\n");
    expect(rows(tsv)).toEqual([{ beg: 1, end: 2, text: "good", speaker: "", section: "" }]);
  });
});
