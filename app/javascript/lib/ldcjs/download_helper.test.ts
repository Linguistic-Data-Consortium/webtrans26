import { describe, expect, test } from "vitest";
import { create_download_tsv } from "./download_helper";

const columns = [ [ "beg", "beg" ], [ "text", "text" ], [ "speaker", "speaker" ] ];

describe("create_download_tsv", () => {
  test("a tab or line break inside a cell can't shift the row's columns", () => {
    const rows = [ { beg: 1.5, text: "one\ttwo\r\nthree", speaker: "A" } ];
    const tsv = create_download_tsv(rows, columns, false, "yes", []);
    expect(tsv).toBe("1.5\tone two three\tA\n");
    expect(tsv.trimEnd().split("\n")).toHaveLength(1);
    expect(tsv.trimEnd().split("\t")).toHaveLength(3);
  });

  test("ordinary cells are written exactly, leading - = + @ included", () => {
    const rows = [ { beg: 0, text: "-um =x +y @z", speaker: null } ];
    expect(create_download_tsv(rows, columns, true, "yes", []))
      .toBe("beg\ttext\tspeaker\n0\t-um =x +y @z\t\n");
  });
});
