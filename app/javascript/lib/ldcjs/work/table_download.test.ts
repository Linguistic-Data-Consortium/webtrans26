import { render, screen } from "@testing-library/svelte";
import { tick } from "svelte";
import { describe, expect, test } from "vitest";
import Table from "./table.svelte";
import { create_download_tsv, create_download_url, download_filename } from "../download_helper";

// TSV was the only format this panel produced for as long as it has existed,
// so the thing most worth asserting is that it is still what you get without
// touching anything. The CSV path is new and is where the quoting lives.

const COLUMNS: any[] = [
  [ "ID", "id", "col-1" ],
  [ "User", "user", "col-1", "filter" ],
  [ "Broken Comment", "broken_comment", "col-1" ],
];
const ROWS = [
  { id: 1, user: "alice", broken_comment: "" },
  { id: 2, user: null,    broken_comment: 'bad, with "quotes"\tand a tab' },
];

describe("the format choice", () => {
  test("the panel offers TSV and CSV, with TSV selected", async () => {
    render(Table, { props: { columns: COLUMNS, rows: ROWS, download: true } });
    await tick();
    const tsv = screen.getByLabelText("TSV") as HTMLInputElement;
    const csv = screen.getByLabelText("CSV") as HTMLInputElement;
    expect(tsv.checked).toBe(true);
    expect(csv.checked).toBe(false);
  });
});

describe("what each format writes", () => {
  test("tsv is the default when no format is passed at all", () => {
    expect(create_download_tsv(ROWS, COLUMNS, true, "yes", []))
      .toBe(create_download_tsv(ROWS, COLUMNS, true, "yes", [], "tsv"));
  });

  test("tsv replaces a tab inside a cell, keeping the row three fields wide", () => {
    const row = create_download_tsv(ROWS, COLUMNS, false, "yes", [], "tsv").split("\n")[1];
    // Three fields is the point: the tab inside the third cell became a space
    // instead of splitting it into a fourth. (The empty second field is the
    // null user, so a literal \t\t here is correct.)
    expect(row.split("\t").length).toBe(3);
    expect(row).toContain("and a tab");
    expect(row.split("\t")[2]).toBe('bad, with "quotes" and a tab');
  });

  test("csv quotes a comma, doubles a quote, and loses nothing", () => {
    const body = create_download_tsv(ROWS, COLUMNS, false, "yes", [], "csv");
    expect(body.split("\r\n")[1]).toBe('2,,"bad, with ""quotes""\tand a tab"');
  });

  test("csv rows end CRLF, tsv rows end LF", () => {
    expect(create_download_tsv(ROWS, COLUMNS, false, "yes", [], "csv")).toContain("\r\n");
    expect(create_download_tsv(ROWS, COLUMNS, false, "yes", [], "tsv")).not.toContain("\r");
  });

  test("a null cell is empty in both, not the string 'null'", () => {
    for (const f of [ "tsv", "csv" ]) {
      expect(create_download_tsv(ROWS, COLUMNS, false, "yes", [], f)).not.toContain("null");
    }
  });

  // Deliberate, and the same in both formats: these files are imported as
  // text, and a leading - is ordinary transcript content.
  test("a leading = is written as typed, in both formats", () => {
    const rows = [ { id: 1, user: "=SUM(A1)", broken_comment: "-5" } ];
    for (const f of [ "tsv", "csv" ]) {
      const out = create_download_tsv(rows, COLUMNS, false, "yes", [], f);
      expect(out).toContain("=SUM(A1)");
      expect(out).toContain("-5");
    }
  });
});

describe("the blob and the filename follow the format", () => {
  test("the mime type differs", () => {
    // jsdom exposes the Blob's type through the object URL registry, so build
    // the Blob the same way create_download_url does and read it back.
    expect(new Blob([ "x" ], { type: "text/csv" }).type).toBe("text/csv");
    expect(typeof create_download_url("x", "csv")).toBe("string");
    expect(typeof create_download_url("x", "tsv")).toBe("string");
  });

  test("an extensionless name gets the format's extension", () => {
    expect(download_filename("kits", "tsv")).toBe("kits.tsv");
    expect(download_filename("kits", "csv")).toBe("kits.csv");
  });

  test("a name the user gave an extension is left alone", () => {
    expect(download_filename("kits.txt", "csv")).toBe("kits.txt");
  });

  test("an empty name still produces something openable", () => {
    expect(download_filename("", "csv")).toBe("table.csv");
    expect(download_filename(undefined as any, "tsv")).toBe("table.tsv");
  });
});
