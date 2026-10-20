import { render, screen, fireEvent } from "@testing-library/svelte";
import { tick } from "svelte";
import { describe, expect, test, vi } from "vitest";
import InputSelect from "./input_select.svelte";

async function mount(props: Record<string, any>) {
  const result = render(InputSelect, { props });
  await tick();
  return result;
}

describe("input_select.svelte", () => {
  test("renders a labeled select with options from `values`", async () => {
    await mount({
      label: "Color",
      key: "color",
      value: "red",
      values: ["red", "green", "blue"],
      urlf: vi.fn(),
    });

    const select = screen.getByLabelText("Color") as HTMLSelectElement;
    expect(select.tagName).toBe("SELECT");
    expect(Array.from(select.options).map((o) => o.textContent)).toEqual(["red", "green", "blue"]);
    expect(select.value).toBe("red");
  });

  test("renders object option labels via the `att` prop", async () => {
    const values = [
      { id: 1, name: "alpha" },
      { id: 2, name: "beta" },
    ];
    await mount({
      label: "Project",
      key: "project",
      value: values[0],
      values,
      att: "name",
      urlf: vi.fn(),
    });

    const select = screen.getByLabelText("Project") as HTMLSelectElement;
    expect(Array.from(select.options).map((o) => o.textContent)).toEqual(["alpha", "beta"]);
  });

  test("does not call urlf on initial mount", async () => {
    const urlf = vi.fn(() => Promise.resolve({}));
    await mount({
      label: "Color",
      key: "color",
      value: "red",
      values: ["red", "green"],
      urlf,
    });
    expect(urlf).not.toHaveBeenCalled();
  });

  test("calls urlf with { key: value } on change (no debounce)", async () => {
    const urlf = vi.fn(() => Promise.resolve({ color: "green" }));
    await mount({
      label: "Color",
      key: "color",
      value: "red",
      values: ["red", "green", "blue"],
      urlf,
    });

    const select = screen.getByLabelText("Color") as HTMLSelectElement;
    await fireEvent.change(select, { target: { value: "green" } });

    expect(urlf).toHaveBeenCalledWith({ color: "green" });
  });

  test("when `att` set and non-meta, extracts the id field of the selected object", async () => {
    const values = [
      { id: 1, name: "alpha" },
      { id: 2, name: "beta" },
    ];
    const urlf = vi.fn(() => Promise.resolve({}));
    await mount({
      label: "Project",
      key: "project_id",
      value: values[0],
      values,
      att: "name",
      urlf,
    });

    const select = screen.getByLabelText("Project") as HTMLSelectElement;
    select.selectedIndex = 1;
    await fireEvent.change(select);

    expect(urlf).toHaveBeenCalledWith({ project_id: 2 });
  });

  test("wraps under { meta: ... } when meta is truthy (non-att path)", async () => {
    const urlf = vi.fn(() => Promise.resolve({}));
    await mount({
      label: "Color",
      key: "color",
      value: "red",
      values: ["red", "green"],
      urlf,
      meta: true,
    });

    await fireEvent.change(screen.getByLabelText("Color"), { target: { value: "green" } });

    expect(urlf).toHaveBeenCalledWith({ meta: { color: "green" } });
  });

  test("meta + att emits '' when selected id is 0", async () => {
    const values = [
      { id: 0, name: "none" },
      { id: 5, name: "real" },
    ];
    const urlf = vi.fn(() => Promise.resolve({}));
    await mount({
      label: "X",
      key: "x",
      value: values[1],
      values,
      att: "name",
      meta: true,
      urlf,
    });

    const select = screen.getByLabelText("X") as HTMLSelectElement;
    select.selectedIndex = 0;
    await fireEvent.change(select);

    expect(urlf).toHaveBeenCalledWith({ meta: { x: "" } });
  });

  test("does nothing when urlf is not provided", async () => {
    await mount({
      label: "Color",
      key: "color",
      value: "red",
      values: ["red", "green"],
    });
    await fireEvent.change(screen.getByLabelText("Color"), { target: { value: "green" } });
  });
});
