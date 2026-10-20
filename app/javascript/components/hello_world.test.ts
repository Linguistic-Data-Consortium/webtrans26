import { render, screen } from "@testing-library/svelte";
import userEvent from "@testing-library/user-event";
import { describe, expect, test } from "vitest";
import HelloWorld from "./hello_world.svelte";

describe("hello_world.svelte", () => {
  test("greets the default guest when no name prop is given", () => {
    render(HelloWorld);
    expect(screen.getByText(/Hello,/)).toBeInTheDocument();
    expect(screen.getByText("Guest")).toBeInTheDocument();
  });

  test("greets the supplied name", () => {
    render(HelloWorld, { name: "Alice" });
    expect(screen.getByText("Alice")).toBeInTheDocument();
  });

  test("increments the counter on click", async () => {
    const user = userEvent.setup();
    render(HelloWorld, { name: "Alice" });

    const button = screen.getByRole("button");
    expect(button).toHaveTextContent("Clicked 0 times");

    await user.click(button);
    expect(button).toHaveTextContent("Clicked 1 time");

    await user.click(button);
    await user.click(button);
    expect(button).toHaveTextContent("Clicked 3 times");
  });
});
