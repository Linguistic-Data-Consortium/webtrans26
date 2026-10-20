// Cross-component progress signals for the in-app guides.
//
// Any component that knows the user just did something interesting calls
// `mark('milestone_name')` (getting-started guide on the user page) or
// `mark_transcription('milestone_name')` (transcription tool guide). The
// matching guide subscribes and bumps its step to the position mapped to
// that milestone.
//
// Milestones currently understood by the guide (see getting_started_guide.svelte).
// Each one marks the step it's listed under as DONE — the guide advances to
// the NEXT step.
//
// In full mode the guide has 13 slides (0..12). The last slide ("Ready to
// go", Action column) is also the only slide shown in simple mode.
//
//   start                    — initial / no progress yet
//   projects_tab_open        — on the top-level Projects tab              (step 0)
//   project_created          — a project was just created                 (step 1)
//   project_open             — a project's row was clicked / panel open   (step 2)
//   project_tasks_tab_open   — Project Tasks sub-tab is open              (step 3)
//   task_created             — a task was just created                    (step 4)
//   task_open                — a task's row was clicked / panel open      (step 5)
//   workflow_changed         — task workflow was switched (to Orderly)    (step 6)
//   task_members_tab_open    — Task Members sub-tab is open               (step 7)
//   task_member_added        — user added themselves to the task          (step 8)
//   kits_tab_open            — Kits sub-tab is open                       (step 9)
//   kit_created              — at least one kit exists on the task        (step 10)
//   work_started             — entered the waveform editor                (step 11)
//
// Adding a new milestone:
//   1. Pick a short name.
//   2. Add a `mark('your_name')` call wherever the action completes.
//   3. Add `your_name: <step index>` to milestone_step in the guide.
//
// Calling mark with a milestone that isn't in milestone_step is a no-op,
// so it's safe to add markers ahead of guide content.

import { writable } from "svelte/store";

export const guide_milestone = writable("start");

export function mark(name) {
    guide_milestone.set(name);
}

// Milestones understood by the transcription guide (see
// lib/transcription_guide.svelte). Each one marks a step as DONE — the guide
// advances to the NEXT step (same "step <= target → step = target + 1" rule
// as the getting-started guide).
//
//   start             — initial / no progress yet
//   waveform_click    — user clicked the waveform to position the cursor
//   space_press       — user pressed the space bar (start / stop playback)
//   scrollbar_click   — user clicked / started dragging the scrollbar
//   selection_drawn   — user finished a click-drag that produced a non-empty selection
//   segment_created   — user pressed Enter on a selection to create a transcript segment
//   transcript_committed — user pressed Enter inside a transcript textarea to finish a line
//   transcript_line_clicked — user clicked on a transcription row in the segments panel
//   focus_to_keyboard — user pressed Tab in the text window, moving focus to the keyboard icon
//   focus_to_text     — user pressed Tab on the keyboard icon, moving focus back to the text window
//   segment_deleted   — user clicked the confirmation delete button on the active segment
//   segment_split     — user pressed ',' to split the active segment at the cursor
//   segment_merged    — user pressed 'm' to merge the active segment with the following one
//   selection_adjusted — user dragged an end of the red selection region to lengthen/shorten it
//   zoomed_in         — user pressed 'i' to zoom into the waveform
//   zoomed_out        — user pressed 'o' to zoom back out of the waveform
//   mode_to_selection — user switched to Selection mode (via 'b' or 'e')
//   mode_to_cursor    — user switched back to Cursor mode (via 'c')
//   mode_to_window    — user switched to Window mode (via 'w')
//   window_moved      — user scrolled the waveform window with a home key in Window mode
//   cursor_moved      — user moved the red cursor with a home key in Cursor mode
//   segment_navigated — user pressed Up / Down to move to the previous / next transcript segment
//   help_opened       — user pressed 'h' to open the main help / cheat-sheet dialog
//   cursor_positioned — user moved the mouse over the waveform, moving the red cursor
//   selection_edge_moved — user nudged a selection edge with d/f/j/k in Selection mode
//
// Adding a new milestone:
//   1. Pick a short name.
//   2. Add a `mark_transcription('your_name')` call wherever the action
//      completes.
//   3. Add `your_name: <step index>` to milestone_step in the guide.

export const transcription_milestone = writable("start");

// Bounce through 'start' so calling mark_transcription with the same name
// twice still notifies subscribers (svelte's writable skips same-value sets
// for primitives, which would otherwise drop the second space press on the
// "Press space again to stop" slide).
export function mark_transcription(name) {
    if (name !== "start") transcription_milestone.set("start");
    transcription_milestone.set(name);
}
