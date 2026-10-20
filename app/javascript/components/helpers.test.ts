import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

// The toast is the only thing these functions produce, so it is what the tests
// read. Mocked rather than rendered — what matters is the text handed to it.
vi.mock("svelte-sonner", () => ({
  toast: { error: vi.fn(), success: vi.fn() },
}));

import { toast } from "svelte-sonner";
import { flash, response, ok_reload } from "./helpers";

// Controllers answer with { error: … } as either a string — 'Permission denied.'
// from allow() — or a list of model error messages. Joining a string throws,
// and the throw happens inside the fetch handler, so the toast never appears
// and the denial reads to the user as a silent success.
//
// Both shapes are tested at all three call sites because the guard used to live
// at one of them: ok_reload had it, flash and response did not, and both of
// those are on the path every permission denial takes.
describe("an error of either shape reaches the toast", () => {
  beforeEach(() => {
    vi.mocked(toast.error).mockClear();
    vi.mocked(toast.success).mockClear();
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe.each([
    ["flash", (data: unknown) => flash(data, "name")],
    ["response", (data: unknown) => response(data, undefined, undefined)],
    ["ok_reload", (data: unknown) => ok_reload(data, () => {})],
  ])("%s", (_name, call) => {
    test("a string error is shown as itself", () => {
      call({ error: "Permission denied." });

      expect(toast.error).toHaveBeenCalledWith("Permission denied.");
    });

    test("a list of errors is joined", () => {
      call({ error: ["Name can't be blank", "Path is invalid"] });

      expect(toast.error).toHaveBeenCalledWith("Name can't be blank Path is invalid");
    });

    test("a missing response says so rather than reading its fields", () => {
      call(null);

      expect(toast.error).toHaveBeenCalledWith("bad response");
    });
  });
});

// The success paths, so a change to the error handling can't quietly take one
// of them with it.
describe("the paths that aren't errors", () => {
  beforeEach(() => {
    vi.mocked(toast.error).mockClear();
    vi.mocked(toast.success).mockClear();
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("flash names the field it updated and the value it now holds", () => {
    flash({ name: "kit one" }, "name");

    expect(toast.success).toHaveBeenCalledWith("updated name to kit one");
    expect(toast.error).not.toHaveBeenCalled();
  });

  test("response calls successf on a create, and deletedf only on a delete", () => {
    const successf = vi.fn();
    const deletedf = vi.fn();

    response({ name: "kit one" }, successf, deletedf);

    expect(toast.success).toHaveBeenCalledWith("created kit one");
    expect(successf).toHaveBeenCalled();
    expect(deletedf).not.toHaveBeenCalled();
  });

  test("response reports a delete and calls both callbacks", () => {
    const successf = vi.fn();
    const deletedf = vi.fn();

    response({ deleted: "Kit 1 has been deleted." }, successf, deletedf);

    expect(toast.success).toHaveBeenCalledWith("Kit 1 has been deleted.");
    expect(deletedf).toHaveBeenCalled();
    expect(successf).toHaveBeenCalled();
  });

  test("ok_reload reloads after a second, and not before", () => {
    const reload = vi.fn();

    ok_reload({ ok: "Saved." }, reload);

    expect(toast.success).toHaveBeenCalledWith("Saved.");
    expect(reload).not.toHaveBeenCalled();

    vi.advanceTimersByTime(1000);
    expect(reload).toHaveBeenCalled();
  });

  test("ok_reload reloads even when the server refused", () => {
    const reload = vi.fn();

    ok_reload({ error: "Permission denied." }, reload);

    vi.advanceTimersByTime(1000);
    expect(reload).toHaveBeenCalled();
  });
});
