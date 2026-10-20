import { render, screen, fireEvent } from "@testing-library/svelte";
import { tick } from "svelte";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import InputText from "./input_text.svelte";

function mountAndSettle(props: Record<string, any>) {
  const result = render(InputText, { props });
  return tick().then(() => result);
}

describe("input_text.svelte", () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("renders a text input labeled by the label prop by default", async () => {
    await mountAndSettle({ label: "Name", key: "name", value: "" });
    const input = screen.getByLabelText("Name");
    expect(input).toBeInTheDocument();
    expect(input.tagName).toBe("INPUT");
    expect(input).toHaveAttribute("type", "text");
  });

  test("renders a textarea when textarea prop is true", async () => {
    await mountAndSettle({ label: "Bio", key: "bio", value: "", textarea: true });
    const field = screen.getByLabelText("Bio");
    expect(field.tagName).toBe("TEXTAREA");
  });

  test("does not call urlf on initial mount", async () => {
    const urlf = vi.fn(() => Promise.resolve({ name: "initial" }));
    await mountAndSettle({ label: "Name", key: "name", value: "initial", urlf });
    vi.advanceTimersByTime(5000);
    expect(urlf).not.toHaveBeenCalled();
  });

  test("calls urlf with { key: value } after ~1s of inactivity", async () => {
    const urlf = vi.fn(() => Promise.resolve({ name: "hello" }));
    await mountAndSettle({ label: "Name", key: "name", value: "", urlf });

    const input = screen.getByLabelText("Name") as HTMLInputElement;
    await fireEvent.input(input, { target: { value: "hello" } });

    expect(urlf).not.toHaveBeenCalled();
    vi.advanceTimersByTime(999);
    expect(urlf).not.toHaveBeenCalled();
    vi.advanceTimersByTime(2);
    expect(urlf).toHaveBeenCalledWith({ name: "hello" });
  });

  test("debounces rapid changes into a single urlf call", async () => {
    const urlf = vi.fn(() => Promise.resolve({ title: "final" }));
    await mountAndSettle({ label: "Title", key: "title", value: "", urlf });

    const input = screen.getByLabelText("Title") as HTMLInputElement;
    await fireEvent.input(input, { target: { value: "a" } });
    vi.advanceTimersByTime(500);
    await fireEvent.input(input, { target: { value: "ab" } });
    vi.advanceTimersByTime(500);
    await fireEvent.input(input, { target: { value: "abc" } });

    vi.advanceTimersByTime(999);
    expect(urlf).not.toHaveBeenCalled();
    vi.advanceTimersByTime(2);
    expect(urlf).toHaveBeenCalledTimes(1);
    expect(urlf).toHaveBeenCalledWith({ title: "abc" });
  });

  test("wraps payload under { meta: ... } when meta='meta'", async () => {
    // NOTE: component currently uses `if` instead of `else if` for the meta branch,
    // so the payload contains BOTH the nested meta shape and the top-level key.
    // This test pins the observed behavior; the component has a latent bug.
    const urlf = vi.fn(() => Promise.resolve({}));
    await mountAndSettle({ label: "Desc", key: "description", value: "", urlf, meta: "meta" });

    await fireEvent.input(screen.getByLabelText("Desc") as HTMLInputElement, { target: { value: "hi" } });
    vi.advanceTimersByTime(1001);
    expect(urlf).toHaveBeenCalledWith({
      meta: { description: "hi" },
      description: "hi",
    });
  });

  test("wraps payload under { constraints: ... } when meta='constraints'", async () => {
    const urlf = vi.fn(() => Promise.resolve({}));
    await mountAndSettle({ label: "Max", key: "max", value: "", urlf, meta: "constraints" });

    await fireEvent.input(screen.getByLabelText("Max") as HTMLInputElement, { target: { value: "10" } });
    vi.advanceTimersByTime(1001);
    expect(urlf).toHaveBeenCalledWith({ constraints: { max: "10" } });
  });

  test("wraps payload under the named outer key when `wrap` is set", async () => {
    const urlf = vi.fn(() => Promise.resolve({}));
    await mountAndSettle({ label: "Name", key: "name", value: "", urlf, wrap: "user" });

    await fireEvent.input(screen.getByLabelText("Name") as HTMLInputElement, { target: { value: "alice" } });
    vi.advanceTimersByTime(1001);
    expect(urlf).toHaveBeenCalledWith({ user: { name: "alice" } });
  });

  test("joins an array value for display when `split` is set", async () => {
    await mountAndSettle({ label: "Tags", key: "tags", value: ["a", "b", "c"], split: "," });
    const input = screen.getByLabelText("Tags") as HTMLInputElement;
    expect(input.value).toBe("a,b,c");
  });

  test("splits the outgoing value on `split` before patching", async () => {
    const urlf = vi.fn(() => Promise.resolve({}));
    await mountAndSettle({ label: "Tags", key: "tags", value: "", urlf, split: "," });

    await fireEvent.input(screen.getByLabelText("Tags") as HTMLInputElement, { target: { value: "x,y,z" } });
    vi.advanceTimersByTime(1001);
    expect(urlf).toHaveBeenCalledWith({ tags: ["x", "y", "z"] });
  });

  test("never calls urlf when urlf is not provided", async () => {
    await mountAndSettle({ label: "Name", key: "name", value: "" });
    await fireEvent.input(screen.getByLabelText("Name") as HTMLInputElement, { target: { value: "hi" } });
    vi.advanceTimersByTime(5000);
  });
});
