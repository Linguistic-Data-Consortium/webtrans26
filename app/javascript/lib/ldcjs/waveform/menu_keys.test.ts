import { describe, expect, test } from "vitest";
import { assign_menu_keys, LETTERS } from "./menu_keys";

// The keymap as the speaker and section menus hand it over: whatever the menu
// has already bound to a function of its own. `n` is "new section" / "new
// speaker"; `r` is "replace speaker", registered only when there's no
// constraint list.
const with_new = { n: "getf" };
const with_new_and_replace = { n: "getf", r: "replacef" };

const named = (n: number) => Array.from({ length: n }, (_, i) => `section_${i + 1}`);
const keys = (result: { key: string | null }[]) => result.map((r) => r.key);

describe("assign_menu_keys", () => {
  test("hands out letters in order", () => {
    expect(keys(assign_menu_keys(["alpha", "beta", "gamma"], {}))).toEqual(["a", "b", "c"]);
  });

  test("keeps each name with its own letter", () => {
    expect(assign_menu_keys(["alpha", "beta"], {})).toEqual([
      { name: "alpha", key: "a" },
      { name: "beta", key: "b" },
    ]);
  });

  test("steps over a letter the menu has claimed", () => {
    // The reported bug: with enough sections to reach N, the fourteenth took
    // the letter "new section" answers to and overwrote it in the keymap. The
    // menu then listed two rows under N and there was no way left to name a
    // section that wasn't already in the list.
    const result = keys(assign_menu_keys(named(14), with_new));
    expect(result).not.toContain("n");
    expect(result[12]).toBe("m");
    expect(result[13]).toBe("o");
  });

  test("the first thirteen are unchanged, so nobody's habits move", () => {
    expect(keys(assign_menu_keys(named(13), with_new)))
      .toEqual(["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m"]);
  });

  test("steps over every claimed letter, not just the first", () => {
    // The speaker menu reserves R for "replace" as well as N for "new".
    const result = keys(assign_menu_keys(named(20), with_new_and_replace));
    expect(result).not.toContain("n");
    expect(result).not.toContain("r");
    expect(result[13]).toBe("o"); // n skipped
    expect(result[16]).toBe("s"); // and r
  });

  test("a claimed letter early in the alphabet is skipped too", () => {
    expect(keys(assign_menu_keys(["one", "two"], { a: "something" }))).toEqual(["b", "c"]);
  });

  test("no name is given a letter that is already spoken for", () => {
    const result = assign_menu_keys(named(24), with_new_and_replace);
    for (const { key } of result) {
      expect(key === null || key in with_new_and_replace).toBe(false);
    }
  });

  test("every letter handed out is distinct", () => {
    const given = keys(assign_menu_keys(named(24), with_new_and_replace)).filter(Boolean);
    expect(new Set(given).size).toBe(given.length);
  });

  test("names past the end of the alphabet get no letter rather than a broken one", () => {
    // Twenty-six letters less the two the menu keeps leaves twenty-four.
    // Running off the end used to assign `undefined`, which bound a real menu
    // entry to a key nobody can press.
    const result = assign_menu_keys(named(26), with_new_and_replace);
    expect(keys(result).slice(0, 24).every((k) => typeof k === "string")).toBe(true);
    expect(keys(result).slice(24)).toEqual([null, null]);
    expect(result[25].name).toBe("section_26");
  });

  test("an empty menu is an empty list", () => {
    expect(assign_menu_keys([], with_new)).toEqual([]);
  });

  test("a menu that has claimed the whole alphabet gives out none", () => {
    const all = Object.fromEntries(LETTERS.map((c) => [c, "taken"]));
    expect(keys(assign_menu_keys(["only"], all))).toEqual([null]);
  });
});
