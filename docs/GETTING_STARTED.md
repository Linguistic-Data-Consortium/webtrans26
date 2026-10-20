# Getting started — your first transcription, end to end

This walks you from a blank instance to actively transcribing a real audio file. We'll use a short public clip as the demo source:

```
https://ldcresearch.s3.us-east-1.amazonaws.com/CarrieFisher.wav
```

Substitute your own URL once you've done the round-trip once.

## 1. Create a project

You land on your dashboard. The default tab is **Work** (your assigned tasks — empty for now).

1. Click the **Projects** tab.
2. Click **Create Project**, name it (e.g. *Demo*), confirm.

The project shows up in the list. Click its row to open its panel.

## 2. Create a task inside the project

Inside the project panel, click the **Project Tasks** tab.

1. Click **Create Task**, name it (e.g. *Demo Transcription*).

## 3. Open the task and switch its workflow to `Orderly`

The `OnTheFly` default won't work for this walkthrough.

1. Click the new task's row to open its panel.
2. Open the **Task Info** tab.
3. Change the workflow to `Orderly` and save.

## 4. Add yourself (and any teammates) to the task

Still inside the project panel:

1. Open the task's row, then its **Task Members** tab.
2. Add your user. You can also add other users here later.

(You can equivalently use the project-level **Project Members** tab to grant project-wide access, then anyone there can pick up the task.)

## 5. Create a kit from the demo audio URL

The task's **Kits** tab is where audio attaches.

1. Open **Kits** under the task.
2. Click **Create Kits (Text Input)**.
3. Paste the demo URL on its own line:

```
https://ldcresearch.s3.us-east-1.amazonaws.com/CarrieFisher.wav
```

4. Click **Parse**, then **Create**.

You should see a new kit row with an auto-generated UID, state `unassigned`.

The source can be a plain audio file (as above) or a JSON wrapper that points
at audio **and** an existing transcript, so the editor opens pre-populated. See
[Input formats](INPUT_FORMATS.md) for both options and the wrapper schema.

## 6. Open the kit and start transcribing

Two paths in:

- **Click the Action link** for that task on the **Work** tab — this enters the `Orderly` workflow, assigns you the next unassigned kit in order, and opens the waveform editor at `/workflows/<task_user_id>/work/<workflow_id>`.

Once in the editor:

- The waveform renders at the top with the mode banner above it.
- Default mode is **Window**. Press `c` to switch to Cursor mode, `b` for Selection, etc.
- Press `space` to play / stop, `enter` to create a segment from the current selection, `tab` to focus the transcript input.
- Press `h` inside the editor for the full cheat sheet, and `h` then `6` for the QWERTY layout view.

That's the round-trip. Edit the URL in step 5 to use your own audio when you're ready.

## Quick reference — page-level keys

These work on the dashboard (any non-editor page):

| Key   | Action                                                                                          |
| ----- | ----------------------------------------------------------------------------------------------- |
| `f`   | Hint mode — letters appear on every clickable element; type the letter to activate              |
| `h`   | Open the page cheat sheet                                                                        |
| `d`   | Open the documentation index                                                                     |
| `s`   | Sign out (with confirmation)                                                                     |
| `j`   | Admin only — jump-to-readonly popup                                                              |

See [KEYBINDINGS](KEYBINDINGS.md) for the underlying mechanism and how to add page-specific keys.
