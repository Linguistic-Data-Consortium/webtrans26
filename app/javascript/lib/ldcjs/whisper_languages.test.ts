import { describe, expect, test } from "vitest";
import { WHISPER_LANGUAGES, language_code, language_name } from "./whisper_languages";

describe("whisper languages", () => {
  test("the library's list, English first", () => {
    expect(WHISPER_LANGUAGES.length).toBe(99);
    expect(WHISPER_LANGUAGES[0]).toEqual(["en", "english"]);
  });

  test("a code from a name in any case, another name the library knows, or a code", () => {
    expect(language_code("French")).toBe("fr");
    expect(language_code("  spanish ")).toBe("es");
    expect(language_code("Castilian")).toBe("es");
    expect(language_code("ja")).toBe("ja");
    expect(language_code("haitian creole")).toBe("ht");
    expect(language_code("klingon")).toBeNull();
    expect(language_code("")).toBeNull();
  });

  test("a name for a code", () => {
    expect(language_name("fr")).toBe("French");
    expect(language_name("ht")).toBe("Haitian Creole");
    expect(language_name("xx")).toBe("xx");
  });
});
