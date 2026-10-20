import { render, screen, fireEvent } from "@testing-library/svelte";
import userEvent from "@testing-library/user-event";
import { tick } from "svelte";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { getp } from "https://cdn.jsdelivr.net/gh/Linguistic-Data-Consortium/ldcjs@0.0.3/src/getp.js";
import Header from "./header.svelte";

function seedOnMountDom() {
  document.body.innerHTML = '<div id="oldsignout"></div><div id="newsignout"></div>';
}

describe("header.svelte", () => {
  beforeEach(() => {
    seedOnMountDom();
    vi.mocked(getp).mockClear();
  });

  afterEach(() => {
    document.body.innerHTML = "";
  });

  test("renders the open button and basic nav items by default", async () => {
    render(Header, { user: "alice", kitid: null, kituid: null, locked: false });
    await tick();

    expect(screen.getByRole("button", { name: "header" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Home" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Documentation" })).toBeInTheDocument();
    expect(screen.getByText("alice")).toBeInTheDocument();
  });

  test("does not render kit details when kitid is null", async () => {
    render(Header, { user: "alice", kitid: null, kituid: null, locked: false });
    await tick();
    expect(document.getElementById("kit_uid")).toBeNull();
  });

  test("renders kit uid and task slot when kitid is present", async () => {
    render(Header, { user: "alice", kitid: 42, kituid: "kit-uid-42", locked: false });
    await tick();

    expect(document.getElementById("kit_uid")?.textContent).toBe("kit-uid-42");
    expect(document.getElementById("task_name")).not.toBeNull();
    expect(screen.queryByRole("button", { name: "unlock" })).toBeNull();
  });

  test("renders the unlock button when kit is locked and clicking it calls getp", async () => {
    (getp as ReturnType<typeof vi.fn>).mockResolvedValueOnce({ ok: true });
    const reload = vi.fn();
    Object.defineProperty(window, "location", {
      configurable: true,
      value: { reload },
    });

    render(Header, { user: "alice", kitid: 42, kituid: "kit-42", locked: true });
    await tick();

    const unlock = screen.getByRole("button", { name: "unlock" });
    await fireEvent.click(unlock);

    expect(getp).toHaveBeenCalledWith("/kits/42/unlock_tree");
  });

  test("open button swaps to the input view, and the close (e) button returns to the nav view", async () => {
    const user = userEvent.setup();
    render(Header, { user: "alice", kitid: null, kituid: null, locked: false });
    await tick();

    await user.click(screen.getByRole("button", { name: "header" }));
    expect(screen.getByRole("button", { name: "e" })).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Home" })).toBeNull();

    await user.click(screen.getByRole("button", { name: "e" }));
    expect(screen.getByRole("link", { name: "Home" })).toBeInTheDocument();
  });

  test("onMount does not throw when oldsignout/newsignout are present", async () => {
    // Seeded DOM includes #oldsignout and #newsignout. The component's onMount
    // does x.replaceWith(y) — we just assert mount completes cleanly and #newsignout ends up in place.
    render(Header, { user: "alice", kitid: null, kituid: null, locked: false });
    await tick();
    expect(document.getElementById("newsignout")).not.toBeNull();
  });
});
