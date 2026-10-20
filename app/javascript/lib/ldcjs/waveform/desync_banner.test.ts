import { render, screen } from "@testing-library/svelte";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { report_desync, desync_clear } from "./desync.svelte";
import DesyncBanner from "./desync_banner.svelte";

// The banner is the whole point of detecting a divergence: before it, a value
// mismatch went to console.error, an 'add' mismatch threw inside a function
// that didn't exist, and a locked tree styled an element no view renders. An
// annotator could keep typing into a page whose writes were being refused.
describe("desync_banner.svelte", () => {
  beforeEach(() => {
    desync_clear();
    vi.spyOn(console, "error").mockImplementation(() => {});
  });

  afterEach(() => desync_clear());

  test("shows nothing while the page and server agree", () => {
    render(DesyncBanner);

    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("appears once a divergence is reported, saying what and what to do", async () => {
    report_desync("A change didn't save as typed.");
    render(DesyncBanner);

    const alert = screen.getByRole("alert");
    expect(alert).toHaveTextContent("out of step with the server");
    expect(alert).toHaveTextContent("A change didn't save as typed.");
    expect(alert).toHaveTextContent("Reload");
  });

  // Assertive, because it appears while the annotator is typing and the thing
  // they are typing into is no longer being saved.
  test("announces itself to a screen reader", () => {
    report_desync("Another session is editing this transcript.");
    render(DesyncBanner);

    expect(screen.getByRole("alert")).toHaveAttribute("aria-live", "assertive");
  });

  test("offers a reload and no way to dismiss it", () => {
    report_desync("A change was refused by the server.");
    render(DesyncBanner);

    const buttons = screen.getAllByRole("button");
    expect(buttons).toHaveLength(1);
    expect(buttons[0]).toHaveTextContent("Reload");
  });

  test("the reload button reloads", async () => {
    const reload = vi.fn();
    Object.defineProperty(window, "location", {
      value: { ...window.location, reload },
      writable: true,
    });

    report_desync("A change didn't save as typed.");
    render(DesyncBanner);
    screen.getByRole("button").click();

    expect(reload).toHaveBeenCalled();
  });

  // The technical detail belongs in the console and a bug report, not in front
  // of someone who needs to know whether to reload.
  test("keeps the technical detail out of the banner", () => {
    report_desync("A change didn't save as typed.", { sent_value: { value: "typed" } });
    render(DesyncBanner);

    expect(screen.getByRole("alert")).not.toHaveTextContent("sent_value");
  });
});
