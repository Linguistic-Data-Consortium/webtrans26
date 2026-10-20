# Page-level keybindings

Every page that mounts `<PageKeyControls />` (see `app/javascript/lib/page_key_controls.svelte`) gets the same set of global shortcuts. They're skipped while focus is in an input/textarea/select or an open `<dialog>`, so they don't fight with normal typing or with modal dialogs.

| Key   | Action                                                                                          |
| ----- | ----------------------------------------------------------------------------------------------- |
| `f`   | Hint mode — every visible actionable element gets a letter overlay; type the letter to activate |
| `h`   | Open the page cheat sheet                                                                       |
| `d`   | Navigate to `/documentation`                                                                    |
| `s`   | Sign out (submits the hidden `#newsignout` form rendered by the layout)                         |
| `Esc` | Cancel hint mode or close any open dialog                                                       |

## Hint mode (`f`) details

- The selector targets `a[href]`, buttons, `[role="button"]`, form controls, `summary`, anything with `[data-hintable]`, and anything with a non-`-1` `tabindex`. Tag an element with `data-no-hint` to skip it.
- When one hintable element is nested inside another (e.g. a `Tooltip.Trigger` inside a `Tabs.Trigger`), only the outer one gets a hint — the inner is treated as part of the same logical action.
- Letters are assigned in DOM order: `a`, `b`, `c`, … up to 26. Past 26 it switches to two-letter combos (`aa`, `ab`, …) and shows an orange ring on the badges that match your typed prefix.
- Letters/clicks: links and buttons get `.click()`; inputs/selects/contenteditables get `.focus()` (with an extra click for checkboxes and radios).

## Adding page-specific keys

`PageKeyControls` accepts an `extraBindings` prop that the cheat sheet will render alongside the built-ins:

```svelte
<PageKeyControls extraBindings={[
    { key: 'n', desc: 'Create a new project' },
    { key: 'r', desc: 'Refresh the project list' }
]} />
```

Handling the keystroke itself is the page's responsibility — `extraBindings` only updates what the cheat sheet displays. Wire up the actual handlers in the page's own component.

## Waveform editor

The waveform editor (`app/javascript/lib/ldcjs/waveform/`) has its own keybinding system driven by `bindings.js`. Open its cheat sheet from inside the editor with `h`, and the QWERTY-layout view with `h` then `6`. See [USER_GUIDE](USER_GUIDE.md) for the full reference.
