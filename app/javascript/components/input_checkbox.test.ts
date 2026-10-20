import { render, screen, fireEvent } from "@testing-library/svelte";
import { tick } from "svelte";
import { describe, expect, test, vi } from "vitest";
import InputCheckbox from "./input_checkbox.svelte";

async function mount(props: Record<string, any>) {
  const result = render(InputCheckbox, { props });
  await tick();
  return result;
}

describe("input_checkbox.svelte", () => {
  test("renders a labeled checkbox reflecting the initial value", async () => {
    await mount({ label: "Accept", key: "accept", value: true, urlf: vi.fn() });
    const checkbox = screen.getByLabelText("Accept") as HTMLInputElement;
    expect(checkbox.type).toBe("checkbox");
    expect(checkbox.checked).toBe(true);
  });

  test("starts unchecked when initial value is false", async () => {
    await mount({ label: "Accept", key: "accept", value: false, urlf: vi.fn() });
    const checkbox = screen.getByLabelText("Accept") as HTMLInputElement;
    expect(checkbox.checked).toBe(false);
  });

  test("does not call urlf on initial mount", async () => {
    const urlf = vi.fn(() => Promise.resolve({}));
    await mount({ label: "Accept", key: "accept", value: false, urlf });
    expect(urlf).not.toHaveBeenCalled();
  });

  test("toggling calls urlf with { key: key } when meta is not set", async () => {
    // NOTE: the plain branch of the component uses `x[k] = k` — the key is sent as both
    // the field name AND the value. That's how the component behaves today.
    const urlf = vi.fn(() => Promise.resolve({}));
    await mount({ label: "Accept", key: "accept", value: false, urlf });

    const checkbox = screen.getByLabelText("Accept") as HTMLInputElement;
    await fireEvent.click(checkbox);

    expect(urlf).toHaveBeenCalledWith({ accept: "accept" });
  });

  test("toggling with meta='meta' wraps under meta and uses the boolean value", async () => {
    const urlf = vi.fn(() => Promise.resolve({}));
    await mount({ label: "On", key: "on", value: false, urlf, meta: "meta" });

    const checkbox = screen.getByLabelText("On") as HTMLInputElement;
    await fireEvent.click(checkbox);

    expect(urlf).toHaveBeenCalledWith({ meta: { on: true } });
  });

  test("toggling with meta='constraints' wraps under constraints", async () => {
    const urlf = vi.fn(() => Promise.resolve({}));
    await mount({ label: "Strict", key: "strict", value: false, urlf, meta: "constraints" });

    await fireEvent.click(screen.getByLabelText("Strict"));

    expect(urlf).toHaveBeenCalledWith({ constraints: { strict: true } });
  });

  test("respects the disabled prop", async () => {
    await mount({ label: "Accept", key: "accept", value: false, urlf: vi.fn(), disabled: true });
    const checkbox = screen.getByLabelText("Accept") as HTMLInputElement;
    expect(checkbox).toBeDisabled();
  });

  test("does nothing when urlf is not provided", async () => {
    await mount({ label: "Accept", key: "accept", value: false });
    await fireEvent.click(screen.getByLabelText("Accept"));
  });
});
