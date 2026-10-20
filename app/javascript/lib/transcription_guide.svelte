<script>
    // Floating bottom-right card that introduces the transcription tool.
    // Auto-opens on the user's first visit (tracked per-user via localStorage)
    // and can be reopened with `g`. Patterned after lib/getting_started_guide.svelte.
    //
    // Context-aware: subscribes to guide_state.transcription_milestone. When
    // other components call `mark_transcription('something')`, the guide
    // advances to the step associated with that milestone.

    import { onMount, untrack } from 'svelte';
    import { transcription_milestone } from './guide_state';
    import { key } from './ldcjs/waveform/stores';

    let { user_id = 'anon' } = $props();

    // Bump the suffix when guide content changes to invalidate older flags.
    const STORAGE_KEY_BASE = 'webtrans26_transcription_guide_dismissed_v1';
    let storage_key = $derived(`${STORAGE_KEY_BASE}_user_${user_id}`);

    let open = $state(false);
    let step = $state(0);
    let jump_menu_open = $state(false); // dropdown that lets the user jump to any slide
    let jump_wrapper = $state(null);    // bind:this on the counter+dropdown — used for click-outside

    // Tracks which prerequisite actions the user has performed AT WHICH
    // STEP, so a slide gated on (say) `space_press` requires a press made
    // while that slide is showing — a press on an earlier slide doesn't
    // satisfy a later gate. Populated from the transcription_milestone
    // store below; same milestone can also advance the visible step.
    let action_done_at_step = $state({});

    function jump_to(i) {
        step = i;
        jump_menu_open = false;
    }

    // Each slide can declare which milestone(s) it responds to:
    //   requires_action: 'name' → Next disabled until milestone fires on
    //     this slide (gate; opens action_done_at_step[step]).
    //   next_on: 'name' → auto-advance to the next slide when milestone
    //     fires. Can be combined with requires_action so the same press
    //     both opens the gate and moves forward.
    let current_milestone = $state('start');
    $effect(() => {
        const unsub = transcription_milestone.subscribe((m) => {
            current_milestone = m;
        });
        return unsub;
    });
    $effect(() => {
        const m = current_milestone;
        if (m === 'start') return;
        // Reading + writing `step` / `action_done_at_step` in the same
        // effect would chain re-runs through Svelte's reactive scheduler.
        // We only want this effect to react to milestone changes, so the
        // mutations are untracked.
        untrack(() => {
            const cs = current_step;
            if (cs.requires_action === m && !action_done_at_step[step]) {
                action_done_at_step = { ...action_done_at_step, [step]: true };
            }
            if (cs.next_on === m) {
                // On the last slide, "next" means close — mirrors what the
                // Done button does. Otherwise advance one slide.
                if (step >= steps.length - 1) close_and_remember();
                else step = step + 1;
            }
        });
    });

    const steps = [
        {
            title: 'Welcome to the transcription tool',
            body: `The waveform shows your audio; the bar above it shows the current <strong>mode</strong> and which step the home keys take. Click the keyboard icon (top-right of the waveform) to focus keys here, then press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">h</kbd> for the full cheat sheet. Reopen this guide anytime with <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">g</kbd>. Full reference in the <a href="/documentation/USER_GUIDE" class="text-indigo-600 underline">Waveform Editor user guide</a>.`
        },
        {
            title: 'Welcome to the Transcription Tutorial!',
            body: `Hi! This tutorial will guide you through how to use the transcription tool. This tool allows you to work remotely, and it was especially designed to help you transcribe quickly and easily.`
        },
        {
            title: 'Introduction',
            body: `Let us start with the basics of the interface and see how to play our file.`
        },
        {
            title: 'The waveform',
            body: `This represents the waveform of an audio file.`,
            // #node-00 wraps the canvases, the cursor/playhead/selection,
            // the timeline ticks, and the scrollbar — i.e. the whole
            // waveform display.
            anchor: '#node-00'
        },
        {
            title: 'The timeline',
            body: `This timeline (in seconds) helps you locate yourself as you navigate through the waveform.`,
            anchor: '.waveform-ticks'
        },
        {
            title: 'The audio file',
            body: `The name of the audio file you are transcribing appears here to the left.`,
            anchor: '.filename'
        },
        {
            title: 'Click to position the cursor',
            body: `To play the audio file, start by clicking anywhere in the waveform window (you should see a red cursor as you move your mouse).`,
            // .node-waveform wraps the canvas and underlines for each channel
            // (mono = one, stereo = two). The union bounding box spans the
            // whole audio-canvas area without including the timeline or
            // scrollbar below it.
            anchor: '.node-waveform',
            // Disable Next until the user clicks the waveform; the click
            // also auto-advances to the next slide.
            requires_action: 'waveform_click',
            next_on: 'waveform_click'
        },
        {
            title: 'Press space to play',
            body: `Now press the space bar on your keyboard to play the audio.`,
            next_on: 'space_press'
        },
        {
            title: 'Press space again to stop',
            body: `Great! You can press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Space</kbd> again to stop playing, or wait until playback is over.`,
            // Disable Next until the user presses space again on this
            // slide; the same press advances to the next slide.
            requires_action: 'space_press',
            next_on: 'space_press'
        },
        {
            title: 'Navigating the waveform',
            body: `Most audio files are long enough that their waveform does not entirely fit at once in the window. In this step, you will learn how to navigate the waveform using your mouse (we will later see how to do it using your keyboard).`,
            next_on: 'space_press'
        },
        {
            title: 'The scrollbar',
            body: `This area can be used to scroll the waveform window. Try clicking in different places to see the rest of the audio.<br><br>Note that the longer the audio file, the narrower the red bar in this area appears.`,
            anchor: '.waveform-scrollbar',
            next_on: 'scrollbar_click'
        },
        {
            title: 'Practice scrolling',
            body: `Great! Note that rendering the waveform takes time, so it might get updated only after you release the click. Feel free to practice more before moving on to the next step.`,
            anchor: '.waveform-scrollbar',
            // Advances on the next scrollbar click (drag-start).
            next_on: 'scrollbar_click'
        },
        {
            title: 'Create an audio segment',
            body: `Transcribing the full audio file as one long single line would be unwise. In this step, we will learn how to create short <em>segments</em> that can easily be transcribed.<br><br>Ideally, segments should be a single sentence long, but many segments will include the last part of one sentence and the first part of another.`
        },
        {
            title: 'Make a selection',
            body: `To start with, let's see how to make a selection: move your cursor over the waveform, click, drag your cursor, and release.<br><br><strong>Important tip:</strong> when transcribing, end your segments at pauses or breaths lasting 0.5 seconds or longer.<br><br>For now, just create a short segment, just 2 sec long for example.`,
            anchor: '.node-waveform',
            next_on: 'selection_drawn'
        },
        {
            title: 'Listen to your selection',
            body: `Great job! You can press the space bar to listen to the selection.`,
            next_on: 'space_press'
        },
        {
            title: 'Create the segment',
            body: `Now press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Enter</kbd> to create a new segment for this selection.`,
            // Disable Next until the segment is created. The guide also
            // stops intercepting Enter while Next is blocked (see
            // on_keydown), so the Enter press falls through to the
            // waveform's key handler and actually creates the segment.
            requires_action: 'segment_created',
            next_on: 'segment_created'
        },
        {
            title: 'Transcribe the segment',
            body: `This text input box is where you transcribe the newly created segment.<br><br>Type some text and then press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Enter</kbd> to finish it.<br><br>Tip: you can listen to the segment again by pressing <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Ctrl</kbd>+<kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Space</kbd>.`,
            // Highlight and put keyboard focus on the active segment's
            // textarea so the user can start typing immediately. Once
            // they press Enter to commit the line, the
            // transcript_committed milestone fires and the slide advances.
            anchor: '.ann-segment',
            focus: 'transcript',
            requires_action: 'transcript_committed',
            next_on: 'transcript_committed'
        },
        {
            title: 'Playback starts automatically',
            body: `Playback starts automatically after you press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Enter</kbd>.<br><br>Note that segments come with blue bars that help you delineate them.`,
            // Stay anchored to the active segment's textarea so the card
            // sits next to the same area of the UI the user just came
            // from (slide 17). After Enter the active textarea rolls
            // over to the next segment, and the ring follows it.
            anchor: '.ann-segment',
            focus: 'transcript',
            next_on: 'transcript_committed'
        },
        {
            title: 'Create another segment',
            body: `Great job! Now try creating another 1-2 sec audio segment not overlapping with the previous one.<br><br>Remember, blue lines indicate audio segments, so you can use them as a guide to create additional, non-overlapping segments for the same speaker. (Different speakers may overlap.)`,
            anchor: '.node-waveform',
            // Next is disabled until the user starts clicking the waveform.
            // The first click also advances to the "how to" reminder so
            // they have the drag-Enter-type-Enter recap while finishing.
            requires_action: 'waveform_click',
            next_on: 'waveform_click'
        },
        {
            title: 'Reminder',
            body: `Click, drag and release, then press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Enter</kbd>.`,
            anchor: '.node-waveform',
            // First half of the drag-Enter-type-Enter recap: finish the
            // selection and press Enter to create the segment. Enter
            // falls through to the waveform because Next is blocked (see
            // on_keydown).
            requires_action: 'segment_created',
            next_on: 'segment_created'
        },
        {
            title: 'Reminder',
            body: `Type some text and press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Enter</kbd> again.`,
            // Focus the transcript textarea so typing goes straight in.
            // Second half of the recap: transcribe the newly created
            // segment and press Enter to commit.
            anchor: '.ann-segment',
            focus: 'transcript',
            requires_action: 'transcript_committed',
            next_on: 'transcript_committed'
        },
        {
            title: 'Well done!',
            body: `Good job! You just created, transcribed and re-heard a particular segment on your own. Let's move on to the next step.`
        },
        {
            title: 'Toggle',
            body: `While working on a segment, the ability to toggle between the waveform window and the text window makes you much more efficient.<br><br>Indeed, you can use keyboard commands from either window, but the two windows use different keys or key combinations. Let us learn how to toggle from one window to the other.`
        },
        {
            title: 'Click a transcription line',
            body: `First, click on this transcription line.`,
            // Highlight the first segment row in the segments panel — the
            // segments container is #segments and each row has class
            // .segment, so :first-of-type picks the first one regardless
            // of which is currently active.
            anchor: '#segments .segment:first-of-type',
            requires_action: 'transcript_line_clicked',
            next_on: 'transcript_line_clicked'
        },
        {
            title: 'Toggle focus with Tab',
            body: `The text window currently has focus: notice the red border around the textbox.<br><br>Toggle focus by pressing the <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Tab</kbd> key on your keyboard.`,
            // Focus the transcript textarea so Tab is handled by the
            // segments Tab binding (→ keyboard_focus action). Advance
            // only on the text→keyboard direction.
            anchor: '.ann-segment',
            focus: 'transcript',
            requires_action: 'focus_to_keyboard',
            next_on: 'focus_to_keyboard'
        },
        {
            title: 'Toggle back with Tab',
            body: `The waveform window now has focus: notice this framed keyboard icon.<br><br>Press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Tab</kbd> again to bring focus back to the text input field.`,
            // Focus is now on the keyboard icon (default) — Tab there
            // fires the waveform's focus_input action. Advance only on
            // the keyboard→text direction.
            anchor: '.keyboard',
            requires_action: 'focus_to_text',
            next_on: 'focus_to_text'
        },
        {
            title: 'Back in the text window',
            body: `Now you're back in the text window (notice its red border).<br><br>Press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Enter</kbd> to play the next audio segment.`,
            // refocus_for_step puts focus back on the textarea so the red
            // focus border appears immediately. Enter in the textarea
            // fires transcript_committed (via set_active_transcript_line_to_next_and_play_current_span)
            // — same key both plays the next segment and advances us.
            anchor: '.ann-segment',
            focus: 'transcript',
            requires_action: 'transcript_committed',
            next_on: 'transcript_committed'
        },
        {
            title: 'Toggle back to the waveform',
            body: `Let's toggle back to the waveform window: press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Tab</kbd>.`,
            // Focus on transcript textarea so Tab there fires the
            // segments Tab binding (→ keyboard_focus action).
            anchor: '.ann-segment',
            focus: 'transcript',
            requires_action: 'focus_to_keyboard',
            next_on: 'focus_to_keyboard'
        },
        {
            title: 'Same key, different behaviour',
            body: `Now press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Enter</kbd> and notice what happens!`,
            // Focus stays on the keyboard icon (default). Setting
            // requires_action disables Next AND makes on_keydown stop
            // intercepting Enter — the press falls through to the
            // waveform's cursor-mode binding, which duplicates the active
            // segment and fires segment_created to advance.
            anchor: '.keyboard',
            requires_action: 'segment_created',
            next_on: 'segment_created'
        },
        {
            title: 'What just happened',
            body: `Unlike in the text window, where <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Enter</kbd> played the next audio segment, pressing <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Enter</kbd> with focus on the waveform window just created another copy of the active segment, as indicated by the double blue bar.`,
            // Point at the duplicated segment's transcript row — that's
            // the currently-active line the user just made a copy of.
            anchor: '.active-segment'
        },
        {
            title: 'Click the new segment',
            body: `To deal with this, click in the input box of the newly created segment in the list above (the empty red-colored line).`,
            // The just-duplicated segment is the currently-active row —
            // highlight it and advance when the user clicks anywhere on
            // it (transcript_line_clicked fires from click_transcript_line).
            anchor: '.active-segment',
            requires_action: 'transcript_line_clicked',
            next_on: 'transcript_line_clicked'
        },
        {
            title: 'Delete the duplicate',
            body: `Now press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Ctrl</kbd>+<kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">d</kbd> on your keyboard to delete this unwanted audio segment, clicking the red 'delete' button to confirm.`,
            // Ctrl+D routes through the text input keymap, so focus needs
            // to be on the transcript textarea. on_keydown ignores keys
            // with a modifier so it won't intercept the shortcut. The
            // segment_deleted milestone fires from delete_active_transcript_line
            // when the confirm button click actually removes the row.
            anchor: '.active-segment',
            focus: 'transcript',
            requires_action: 'segment_deleted',
            next_on: 'segment_deleted'
        },
        {
            title: 'Duplicate removed',
            body: `As you can see, the duplicate segment has now disappeared. You now know how to toggle and delete an unwanted segment.`
        },
        {
            title: 'Split and Merge Segments: Part I',
            body: `As your transcription work progresses, you will find that the edits you want to make to your segments are not limited to deletion.<br><br>Sometimes, you will create one segment and later realize that splitting it in two would be a better option, or the other way around. Maybe you want to exclude a pause or breath of 0.5 seconds or longer, or part of the segment actually contains speech from a different speaker. This tool allows for these adjustments. Let us learn how to split and merge audio segments.`
        },
        {
            title: 'Activate a segment',
            body: `Click on the transcription line of an audio segment to make it active.`,
            // Highlight the first row in the segments panel. Clicking any
            // row still fires transcript_line_clicked → advance.
            anchor: '#segments .segment:first-of-type',
            requires_action: 'transcript_line_clicked',
            next_on: 'transcript_line_clicked'
        },
        {
            title: 'Tab to the waveform',
            body: `Now press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Tab</kbd> to give focus to the waveform window.`,
            // Clicking the row above activated it and put focus on its
            // textarea. Tab from there fires focus_to_keyboard.
            anchor: '.ann-segment',
            focus: 'transcript',
            requires_action: 'focus_to_keyboard',
            next_on: 'focus_to_keyboard'
        },
        {
            title: 'Position the cursor',
            body: `Move your mouse over the waveform window to control the red line cursor and place it where you want to divide the current segment.<br><br><strong>IMPORTANT:</strong> do NOT click, simply move the red cursor.`,
            // Advances as soon as the user moves the mouse over the
            // waveform (channels.svelte's mousemove fires
            // cursor_positioned). No requires_action so Next stays
            // enabled and users can skip if they can't move the mouse
            // for some reason.
            anchor: '.node-waveform',
            next_on: 'cursor_positioned'
        },
        {
            title: 'Split with comma',
            body: `Press the comma <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">,</kbd> key on your keyboard to split the segment where the cursor is.<br><br><strong>IMPORTANT:</strong> do NOT click, simply move the cursor and then press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">,</kbd>.`,
            // Focus on the keyboard icon (default) so the waveform's
            // cursor-mode ',' binding runs (split_segment_at_cursor).
            // passthrough_keys routes ',' straight through the waveform's
            // key store even if focus drifted to the transcript textarea,
            // so the split runs regardless of where focus landed.
            anchor: '.node-waveform',
            passthrough_keys: [','],
            requires_action: 'segment_split',
            next_on: 'segment_split'
        },
        {
            title: 'Segment split',
            body: `The former active segment has been split in two: there now are two blue bars where there used to be one, and a new empty transcription line appeared in the list below the waveform.`,
            // Highlight the waveform where the newly-doubled blue bars
            // are visible.
            anchor: '.node-waveform'
        },
        {
            title: 'Merge with m',
            body: `Now that you know how to split segments in two, we will learn to merge them back!<br><br>To merge them back, simply press the letter <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">m</kbd> on your keyboard: this will merge the new active segment with the next one on its right (the empty one).<br><br>Note that this command works with waveform focus — the framed keyboard icon.`,
            // Focus on the keyboard icon (default) so 'm' triggers the
            // waveform's cursor-mode merge binding. 'm' isn't in the
            // guide's on_keydown switch, so it isn't intercepted.
            // preserve_anchor_rect keeps the card fixed at the previous
            // slide's position (over the waveform), so it doesn't jump
            // to the keyboard icon between "Segment split" and this one.
            preserve_anchor_rect: true,
            requires_action: 'segment_merged',
            next_on: 'segment_merged'
        },
        {
            title: 'Split and merge recap',
            body: `Good job! Remember, when focus is on the waveform window, a keypress on <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">,</kbd> will split the segment at the red cursor, and a keypress on <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">m</kbd> will merge the next segment into the active segment.`
        },
        {
            title: 'Split and Merge: Part II',
            body: `You now know how to split and merge two segments while you are in the waveform window.<br><br>Commands work differently in the waveform window and the text window. For example, simply pressing comma in the text window will just type it instead of dividing the segment.<br><br>So let's see how to do merge and split while focus is on the text window.`
        },
        {
            title: 'Open a segment',
            body: `First, click on a segment to open its input box and give it focus.`,
            // Suggest the first row; any row click fires
            // transcript_line_clicked and advances.
            anchor: '#segments .segment:first-of-type',
            requires_action: 'transcript_line_clicked',
            next_on: 'transcript_line_clicked'
        },
        {
            title: 'Split from the text window',
            body: `Now move the red line cursor (<em>without clicking</em>) to where you want to split.<br><br>Then press the Control and comma keys together (<kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Ctrl</kbd>+<kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">,</kbd>).`,
            // Focus on the transcript textarea so Ctrl+, is handled by
            // the segments input keymap (which routes to
            // split_segment_at_cursor and fires segment_split). The
            // guide's on_keydown bails on modifier keys, so Ctrl+, isn't
            // intercepted.
            anchor: '.node-waveform',
            focus: 'transcript',
            requires_action: 'segment_split',
            next_on: 'segment_split'
        },
        {
            title: 'Merge from the text window',
            body: `You now have two segments.<br><br>Press the Control and <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">m</kbd> keys together (<kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Ctrl</kbd>+<kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">m</kbd>) to merge the two split segments.`,
            // Focus on the transcript textarea; Ctrl+m routes through
            // the segments input keymap to merge_with_following_segment
            // and fires segment_merged. Modifier keys bypass the guide's
            // on_keydown.
            anchor: '.active-segment',
            focus: 'transcript',
            requires_action: 'segment_merged',
            next_on: 'segment_merged'
        },
        {
            title: 'Split and merge complete',
            body: `As you can see, the two split segments are now merged into a single one again.<br><br>You are now able to split and merge two segments both from within the waveform and from within the text window.`
        },
        {
            title: 'Adjust Audio Segments',
            body: `You may have noticed that splitting one segment inserts an empty area between the two new segments: this is one situation where you might need to adjust (shorten or lengthen) an existing segment. You may need to adjust your segments to reflect different, simultaneous speakers, whose segments can overlap.`
        },
        {
            title: 'Pick a segment',
            body: `First, click on a segment in this list.`,
            // Highlight the first row; any row click fires
            // transcript_line_clicked → advance.
            anchor: '#segments .segment:first-of-type',
            requires_action: 'transcript_line_clicked',
            next_on: 'transcript_line_clicked'
        },
        {
            title: 'Adjust the selection',
            body: `Now you should see a red region in the waveform.<br><br>Click either end of that red region and drag your cursor in either direction.`,
            // Highlight the waveform where the red selection sits.
            // selection_adjusted fires only from the edge-drag mouseup
            // path, not from fresh drags, so this specifically detects
            // the user grabbing an end of the current selection.
            anchor: '.node-waveform',
            requires_action: 'selection_adjusted',
            next_on: 'selection_adjusted'
        },
        {
            title: 'Simple as that',
            body: `There you go, it's as simple as that! Drag in one direction to shorten, drag in the other direction to lengthen.`
        },
        {
            title: 'Adjust Audio Segments: Zoom In/Zoom Out',
            body: `Whenever you adjust a segment, you should insert a buffer of 0.1 sec before and after it: this ensures that a word won't be cut off prematurely.<br><br>Precisely measuring 0.1 sec can be difficult, so this tool comes with a built-in zoom in/out function.`
        },
        {
            title: 'Zoom in with i',
            body: `To zoom in, make sure you are in the waveform window (framed keyboard icon), and press the letter key <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">i</kbd> (for <em>in</em>).`,
            // Focus on the keyboard icon (default) so 'i' triggers the
            // waveform's cursor-mode zoom_in binding. 'i' isn't in the
            // guide's on_keydown switch, so it isn't intercepted.
            // Anchor on the waveform so the highlight ring sits on the
            // area that will visibly change when the zoom is applied.
            anchor: '.node-waveform',
            requires_action: 'zoomed_in',
            next_on: 'zoomed_in'
        },
        {
            title: 'Finer timeline',
            body: `As you can see, the timeline intervals are now finer-grained. You can zoom further in by pressing <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">i</kbd> again.`,
            // Highlight the timeline so the user can see the finer ticks.
            // No requires_action — Next stays enabled — but another 'i'
            // press auto-advances.
            anchor: '.waveform-ticks',
            next_on: 'zoomed_in'
        },
        {
            title: 'Zoom out with o',
            body: `To zoom out, press the letter key <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">o</kbd> (for <em>out</em>) while focus is still on the waveform window (framed keyboard icon).`,
            // Focus on the keyboard icon (default) so 'o' triggers the
            // waveform's cursor-mode zoom_out binding. 'o' isn't in the
            // guide's on_keydown switch. Anchor on the waveform so the
            // highlight ring sits on the area that visibly zooms out.
            anchor: '.node-waveform',
            requires_action: 'zoomed_out',
            next_on: 'zoomed_out'
        },
        {
            title: 'Zoom recap',
            body: `Remember, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">i</kbd> to zoom <strong>i</strong>n, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">o</kbd> to zoom <strong>o</strong>ut.`
        },
        {
            title: 'Move Across Audio Segments',
            body: `A few keys perform the same action when pressed from <em>either</em> window.<br><br>Pressing the up and down arrow keys from either window, for example, will move from one audio segment to another.`
        },
        {
            title: 'Check your focus',
            body: `First make sure your focus is either on the waveform window or on the text window.`
        },
        {
            title: 'Arrow keys to navigate',
            body: `Now press the <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Up</kbd> arrow key to go to the last/previous segment, or the <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Down</kbd> arrow key to go to the first/next segment.`,
            // Highlight the segments list. Up/Down aren't in the guide's
            // on_keydown switch, so they fall through to whichever window
            // has focus; both waveform and text handlers route to the
            // prev/next-line action that fires segment_navigated.
            anchor: '#segments',
            requires_action: 'segment_navigated',
            next_on: 'segment_navigated'
        },
        {
            title: 'Practice navigation',
            body: `You can try switching focus and press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Up</kbd> or <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Down</kbd> again if you'd like.<br><br>Note that pressing either key will automatically bring focus back to the input window, so you need to toggle focus if you want to work from the waveform window.<br><br>Once you are ready, we will move to the next step.`
        },
        {
            title: 'Help Menu: General',
            body: `You might forget some key bindings, and there are some that you are not familiar with yet.<br><br>You can review the different key bindings from the help menu. Let us see how to do that.`
        },
        {
            title: 'Open the help menu',
            body: `First, make sure your focus is on the waveform window (framed keyboard icon should be green).<br><br>Then press the <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">h</kbd> key to open the help menu.`,
            // Default keyboard focus so the .keyboard element captures
            // 'h' and MainHelpDialog's key.subscribe fires show_main,
            // which mark_transcriptions help_opened. Anchor on the
            // waveform (same treatment as the other "waveform focus"
            // slides) instead of the keyboard icon.
            anchor: '.node-waveform',
            requires_action: 'help_opened',
            next_on: 'help_opened'
        },
        {
            title: 'Help Menu: Submit',
            body: `We are almost done! There's one last thing we need to see: how to submit your transcription.`
        },
        {
            title: 'Submit your work',
            body: `When you are done with the file, click this checkmark icon to submit your work.`,
            // Highlight the submit button in the top control bar.
            anchor: '.submit-button'
        },
        {
            title: 'Confirm with Done',
            body: `Unless there was a problem with the file, simply click on 'Done'.`,
            // The Done button lives inside the popover that opens when
            // the user clicks the checkmark; if the popover isn't open
            // yet, the anchor won't resolve and the card falls back to
            // its bottom-right corner placement.
            anchor: '.submit-done-button'
        },
        {
            title: 'Training complete!',
            body: `Thank you, this is the end of this transcription training guide! Remember, you can always press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">h</kbd> while in the waveform window to get help with the interface.<br><br>If you wish to take the tutorial again, simply leave this task and open it again.`
        },
    ];

    // Preserved for future use — do NOT append to `steps` above.
    //
    // The Home Keys section below was written against an earlier edition of
    // the waveform's key bindings and no longer matches the tool's actual
    // behaviour (e.g. selection-mode edge nudging, the b/e mode names, and
    // the window-mode home-key scroll pattern have all shifted). Rather than
    // delete the slides, they're parked here so the copy stays around for
    // when the bindings settle and the section can be rewritten and dropped
    // back into `steps`.
    // eslint-disable-next-line no-unused-vars
    const home_keys_unused = [
        {
            title: 'Home Keys: Part I',
            body: `Zooming in and out is not the only way of getting finer-grained control over the waveform.<br><br>In this step, you will learn to control elements from the waveform window using your keyboard.`
        },
        {
            title: 'Pick a line',
            body: `First, click on one of the transcription lines below.`,
            anchor: '#segments .segment:first-of-type',
            requires_action: 'transcript_line_clicked',
            next_on: 'transcript_line_clicked'
        },
        {
            title: 'Tab to the waveform',
            body: `Now that your segment is active, press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">Tab</kbd> to give focus to the waveform window.<br><br><strong>Important:</strong> do NOT click the waveform window, or you will lose the active segment.`,
            anchor: '.ann-segment',
            focus: 'transcript',
            requires_action: 'focus_to_keyboard',
            next_on: 'focus_to_keyboard'
        },
        {
            title: 'Press b for beginning',
            body: `Notice how this reads <em>cursor</em>: this means that key bindings will apply to the red cursor.<br><br>In this step, we want to adjust the beginning/end of the segment. Press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">b</kbd> to control the <strong>b</strong>eginning of the segment.`,
            anchor: '.mode-banner',
            requires_action: 'mode_to_selection',
            next_on: 'mode_to_selection'
        },
        {
            title: 'Move the beginning edge',
            body: `This now reads <em>beg</em>: you are now controlling the beginning of the segment.<br><br>Press the key <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">f</kbd> to move it to the left, or the key <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">j</kbd> to move it to the right.`,
            anchor: '.mode-banner',
            requires_action: 'selection_edge_moved',
            next_on: 'selection_edge_moved'
        },
        {
            title: 'Try it again',
            body: `Press the key <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">f</kbd> to move it to the left, or the key <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">j</kbd> to move it to the right.`,
            anchor: '.mode-banner',
            requires_action: 'selection_edge_moved',
            next_on: 'selection_edge_moved'
        },
        {
            title: 'Practice a little',
            body: `Press the key <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">f</kbd> to move further to the left, or <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">j</kbd> to move further to the right. Feel free to practice a little.`,
            anchor: '.mode-banner',
            requires_action: 'selection_edge_moved',
            next_on: 'selection_edge_moved'
        },
        {
            title: 'Bigger steps',
            body: `You can make bigger steps to the left by using the keys <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">d</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">s</kbd> and <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">a</kbd>, and to the right using the keys <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">k</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">l</kbd> and <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">;</kbd>. The relative positions of those keys on a standard US keyboard reflect the magnitude of the step.<br><br>Press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">c</kbd> when you are satisfied to go back to <em>cursor</em> mode, thus validating the new beginning position.`,
            anchor: '.mode-banner',
            requires_action: 'mode_to_cursor',
            next_on: 'mode_to_cursor'
        },
        {
            title: 'Press e for end',
            body: `Now press the key <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">e</kbd> to control the <strong>e</strong>nd of the segment.`,
            anchor: '.mode-banner',
            requires_action: 'mode_to_selection',
            next_on: 'mode_to_selection'
        },
        {
            title: 'Move the end edge',
            body: `This now reads <em>end</em>: you are now controlling the end of the segment.<br><br>As before, press the key <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">f</kbd> to move it to the left, or the key <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">j</kbd> to move it to the right.`,
            anchor: '.mode-banner',
            requires_action: 'selection_edge_moved',
            next_on: 'selection_edge_moved'
        },
        {
            title: 'Practice and validate',
            body: `The key bindings are the same: <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">f</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">d</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">s</kbd> and <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">a</kbd> move to the left, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">j</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">k</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">l</kbd> and <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">;</kbd> move to the right. Feel free to practice, and press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">c</kbd> when you are done.`,
            anchor: '.mode-banner',
            requires_action: 'mode_to_cursor',
            next_on: 'mode_to_cursor'
        },
        {
            title: 'Home Keys: Part II',
            body: `These eight keys (<kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">a</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">s</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">d</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">f</kbd> and <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">j</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">k</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">l</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">;</kbd>) are called the <em>home keys</em>. You just saw how you can use them to control the beginning and the end of a segment; you will now see how to use them to scroll the waveform window and control the red cursor's position.`
        },
        {
            title: 'Click the waveform',
            body: `First, click anywhere in the waveform window.`,
            anchor: '.node-waveform',
            requires_action: 'waveform_click',
            next_on: 'waveform_click'
        },
        {
            title: 'Press w for window mode',
            body: `Now press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">w</kbd> to change from cursor to <em>window</em> mode.`,
            anchor: '.mode-banner',
            requires_action: 'mode_to_window',
            next_on: 'mode_to_window'
        },
        {
            title: 'Scroll with the home keys',
            body: `You can now use the home keys to scroll the waveform window to the right (<kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">j</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">k</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">l</kbd> and <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">;</kbd>) and to the left (<kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">f</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">d</kbd>, <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">s</kbd> and <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">a</kbd>).`,
            anchor: '.node-waveform',
            requires_action: 'window_moved',
            next_on: 'window_moved'
        },
        {
            title: 'Move the cursor with home keys',
            body: `In cursor mode, the home keys will simply move the red cursor, allowing you for example to precisely reach a splitting point. Try pressing one of the home keys and see the cursor move.`,
            anchor: '.node-waveform',
            requires_action: 'cursor_moved',
            next_on: 'cursor_moved'
        },
        {
            title: 'Home keys recap',
            body: `That's pretty much it for the home keys. Remember, they will work when focus is on the waveform window (framed keyboard icon).<br><br>Feel free to practice a little more before moving to the next step.`
        }
    ];

    let is_last = $derived(step >= steps.length - 1);
    let is_first = $derived(step === 0);
    let current_step = $derived(steps[step] || steps[0]);
    // Steps may set `requires_action: 'name'` to disable the Next button
    // until the user performs the action ON THIS STEP. Once the matching
    // milestone fires while this step is showing (recorded in
    // action_done_at_step[step]), the gate opens.
    let next_blocked = $derived(
        current_step.requires_action != null &&
        !action_done_at_step[step]
    );

    // Three-tier positioning. The card lives at:
    //   - Slide 0 (Welcome) → bottom-right corner (unobtrusive).
    //   - Steps with `anchor` → next to the matched element (with ring).
    //   - Otherwise → centered horizontally, below the waveform.
    let anchor_rect = $state(null);
    let waveform_rect = $state(null);

    // Anchor watcher: when the current step has an `anchor`, find the
    // element(s) and store the union bounding box (so a multi-element
    // target like a column still gets one ring). Last selector in a
    // comma-separated list wins, same pattern as the users-page guide.
    $effect(() => {
        if (!open) { anchor_rect = null; return; }
        // Slides with preserve_anchor_rect: true keep the previous
        // slide's card position. The previous effect run left
        // anchor_rect at its last computed value; by skipping the
        // recompute (and the setInterval), that value stays put even if
        // the underlying DOM element (e.g. .node-waveform after a
        // segment split) has changed size.
        if (current_step.preserve_anchor_rect) return;
        const selector = current_step.anchor;
        if (!selector) { anchor_rect = null; return; }
        const candidates = selector.split(',').map(s => s.trim()).filter(Boolean);
        const update = () => {
            let elements = [];
            for (const s of candidates) {
                const matches = Array.from(document.querySelectorAll(s));
                if (matches.length) elements = matches;
            }
            if (!elements.length) { anchor_rect = null; return; }
            let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity;
            for (const el of elements) {
                const r = el.getBoundingClientRect();
                if (r.width === 0 && r.height === 0) continue;
                if (r.left < left) left = r.left;
                if (r.top < top) top = r.top;
                if (r.right > right) right = r.right;
                if (r.bottom > bottom) bottom = r.bottom;
            }
            if (!isFinite(left)) { anchor_rect = null; return; }
            anchor_rect = { left, top, right, bottom, width: right - left, height: bottom - top };
        };
        update();
        const interval = setInterval(update, 100);
        window.addEventListener('scroll', update, true);
        window.addEventListener('resize', update);
        return () => {
            clearInterval(interval);
            window.removeEventListener('scroll', update, true);
            window.removeEventListener('resize', update);
        };
    });

    // Waveform watcher: tracks the bottom of the waveform display so the
    // default "centered below the waveform" placement follows the audio
    // even if the layout shifts.
    $effect(() => {
        if (!open) { waveform_rect = null; return; }
        const update = () => {
            const el = document.querySelector('#node-00');
            if (!el) { waveform_rect = null; return; }
            const r = el.getBoundingClientRect();
            if (r.width === 0 && r.height === 0) { waveform_rect = null; return; }
            waveform_rect = { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height };
        };
        update();
        const interval = setInterval(update, 250);
        window.addEventListener('scroll', update, true);
        window.addEventListener('resize', update);
        return () => {
            clearInterval(interval);
            window.removeEventListener('scroll', update, true);
            window.removeEventListener('resize', update);
        };
    });

    const CARD_W = 384;
    let card_style = $derived.by(() => {
        // Slide 0 always uses the bottom-right corner — keeps the welcome
        // out of the way of the actual UI.
        if (step === 0) return 'bottom: 1rem; right: 1rem;';

        // If the step has an anchor and it resolved, sit next to it.
        if (anchor_rect) {
            const est_h = 220;
            const margin = 12;
            let left = anchor_rect.left;
            const max_left = window.innerWidth - CARD_W - margin;
            if (left > max_left) left = max_left;
            if (left < margin) left = margin;
            const space_below = window.innerHeight - anchor_rect.bottom;
            const space_above = anchor_rect.top;
            let top;
            if (space_below >= est_h || space_below >= space_above) {
                top = anchor_rect.bottom + margin;
            } else {
                top = anchor_rect.top - est_h - margin;
            }
            if (top < margin) top = margin;
            const max_top = window.innerHeight - margin - 60;
            if (top > max_top) top = max_top;
            return `top: ${top}px; left: ${left}px;`;
        }

        // No anchor — centered horizontally, below the waveform.
        if (waveform_rect) {
            const margin = 12;
            let top = waveform_rect.bottom + margin;
            let left = Math.max(margin, Math.round((window.innerWidth - CARD_W) / 2));
            const max_top = window.innerHeight - margin - 60;
            if (top > max_top) top = max_top;
            return `top: ${top}px; left: ${left}px;`;
        }

        // Waveform isn't in the DOM yet — corner fallback.
        return 'bottom: 1rem; right: 1rem;';
    });

    function show() {
        // Reset the milestone so any prior-session signal (e.g. the user
        // already clicked the waveform once) doesn't immediately bump the
        // guide off step 0 again on manual reopen. Also clear per-step
        // action records so gates start fresh.
        transcription_milestone.set('start');
        action_done_at_step = {};
        step = 0;
        open = true;
    }

    // After any slide change (button click, jump, auto-advance, or initial
    // open), focus returns to the keyboard icon — that's the element whose
    // focus the waveform's key.subscribe depends on, so keys like space,
    // Enter, and the home row only work when it has focus. Slides that
    // involve typing into a transcript can opt into focusing the active
    // textarea instead by setting `focus: 'transcript'` on the slide.
    function refocus_for_step() {
        if (!open) return;
        const target = current_step?.focus || 'keyboard';
        const apply = () => {
            if (target === 'transcript') {
                const ta = document.querySelector('.ann-segment')
                        || document.querySelector('.SegmentList textarea');
                if (ta && document.activeElement !== ta) ta.focus();
            } else {
                // Blur any focused input first — otherwise the transcript
                // textarea keeps eating keys and the guide's Enter/n
                // shortcuts (and the waveform's key bindings) all appear
                // dead until the user manually clicks the keyboard icon.
                const active = document.activeElement;
                if (active && (active.tagName === 'TEXTAREA' || active.tagName === 'INPUT')) {
                    active.blur();
                }
                const kb = document.querySelector('.keyboard');
                if (kb) kb.focus();
            }
        };
        // Two attempts: the first runs shortly after Svelte's DOM update,
        // the second wins if a downstream t_init call in segments.svelte
        // stole focus back after our first attempt.
        setTimeout(apply, 50);
        setTimeout(apply, 200);
    }

    // Run refocus whenever the visible step changes OR the guide opens —
    // covers Next/Back/jump/auto-advance/initial open in one place.
    $effect(() => {
        step; open;
        refocus_for_step();
    });
    function close_and_remember() {
        open = false;
        try { localStorage.setItem(storage_key, '1'); } catch (_) {}
        // The close button (or Skip / Done) had focus; once the guide
        // disappears the browser falls back to <body>, which the
        // waveform's key.subscribe ignores. Return focus to the keyboard
        // icon so the user can keep using the tool right away.
        setTimeout(() => {
            const kb = document.querySelector('.keyboard');
            if (kb) kb.focus();
        }, 50);
    }
    function next() {
        if (next_blocked) return;
        jump_menu_open = false;
        is_last ? close_and_remember() : (step = step + 1);
    }
    function back() {
        jump_menu_open = false;
        if (!is_first) step = step - 1;
    }

    function input_focused() {
        const el = document.activeElement;
        if (!el) return false;
        return el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable;
    }

    function on_keydown(e) {
        if (e.key === 'g') console.log('[tguide] g pressed; open=', open, 'input_focused=', input_focused());
        // Slides can list keys that must reach the waveform regardless of
        // current focus (e.g. ',' on the "Split with comma" slide). We
        // route the key through the waveform's key store directly so
        // it triggers the cursor-mode binding even if focus drifted to
        // the transcript textarea, and we move focus back to .keyboard
        // so subsequent presses are handled the normal way.
        if (open && current_step?.passthrough_keys?.includes(e.key)
                 && !e.ctrlKey && !e.metaKey && !e.altKey) {
            e.preventDefault();
            e.stopImmediatePropagation();
            const active = document.activeElement;
            if (active && (active.tagName === 'TEXTAREA' || active.tagName === 'INPUT')) {
                active.blur();
            }
            const kb = document.querySelector('.keyboard');
            if (kb) kb.focus();
            key.set(e);
            return;
        }
        if (input_focused()) return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        if (!open) {
            if (document.querySelector('dialog[open]')) return;
            if (e.key === 'g') {
                e.preventDefault();
                e.stopImmediatePropagation();
                show();
            }
            return;
        }
        switch (e.key) {
            case 'Escape':
                e.preventDefault();
                e.stopImmediatePropagation();
                // Escape closes the jump menu first, the guide second.
                if (jump_menu_open) jump_menu_open = false;
                else close_and_remember();
                break;
            case 'ArrowRight':
            case 'Enter':
            case 'n':
                // If Next is disabled (slide is waiting on a user action),
                // don't swallow the key — some of these (Enter especially)
                // are the very action the slide is asking for and must
                // reach the waveform's key handler.
                if (next_blocked) return;
                e.preventDefault();
                e.stopImmediatePropagation();
                next();
                break;
            case 'ArrowLeft':
                e.preventDefault();
                e.stopImmediatePropagation();
                back();
                break;
        }
    }

    $effect(() => {
        // Capture phase so we beat the waveform's own keydown listeners.
        console.log('[tguide] attaching keydown listener');
        window.addEventListener('keydown', on_keydown, true);
        return () => window.removeEventListener('keydown', on_keydown, true);
    });

    // Click outside the counter+dropdown closes the jump menu. Listener
    // is only active while the menu is open. Using mousedown (capture)
    // means we run before the counter button's own click handler, so a
    // click on the counter while the menu is open still gets to toggle
    // normally (counter is inside jump_wrapper → no-op here).
    $effect(() => {
        if (!jump_menu_open) return;
        const handler = (e) => {
            if (jump_wrapper && !jump_wrapper.contains(e.target)) {
                jump_menu_open = false;
            }
        };
        window.addEventListener('mousedown', handler, true);
        return () => window.removeEventListener('mousedown', handler, true);
    });

    onMount(() => {
        // The transcription REPL/auto harnesses set this flag (via
        // config.x.transcription_repl → work.html.haml) so the guide never
        // opens during scripted runs — its window keydown handler would
        // otherwise swallow the scripts' Enter/Escape keystrokes.
        if (typeof window !== 'undefined' && window.ldc_work_work?.transcription_repl) return;
        // Auto-open only until the user dismisses it. close_and_remember()
        // writes the flag; `g` reopens the guide at any time afterwards.
        let dismissed = false;
        try { dismissed = !!localStorage.getItem(storage_key); } catch (_) {}
        console.log('[tguide] onMount fired, storage_key=', storage_key, 'dismissed=', dismissed);
        if (!dismissed) show();
    });
</script>

{#if open}
    {#if anchor_rect}
        <!-- Highlight ring around the current step's target. -->
        <div
            class="fixed pointer-events-none z-30 rounded-md ring-4 ring-indigo-500 animate-pulse"
            style="left: {anchor_rect.left}px; top: {anchor_rect.top}px; width: {anchor_rect.width}px; height: {anchor_rect.height}px;"
        ></div>
    {/if}

    <div
        class="fixed z-40 w-[24rem] max-w-[calc(100vw-2rem)] bg-white border border-gray-200 rounded-lg shadow-xl transition-[top,left] duration-200"
        style={card_style}
        role="dialog"
        aria-label="Transcription tool guide"
    >
        <div class="relative px-4 py-2 bg-gradient-to-r from-indigo-50 via-purple-50 to-pink-50 border-b border-gray-200 rounded-t-lg flex items-center justify-between">
            <!-- The wrapper is what the click-outside handler keys off —
                 clicks inside it (counter, dropdown, dropdown items) don't
                 close the menu. The dropdown itself is positioned relative
                 to the header (which has `relative`) so it sits against
                 the card's left edge, not under the counter. -->
            <div class="flex items-center gap-2" bind:this={jump_wrapper}>
                <span class="text-xs font-semibold uppercase tracking-wide text-gray-600">Transcription tool</span>
                <!-- Click the counter to open a list of all slides and jump to one. -->
                <button
                    type="button"
                    onclick={() => jump_menu_open = !jump_menu_open}
                    class="text-[10px] text-gray-500 hover:text-gray-800 cursor-pointer inline-flex items-center gap-0.5"
                    aria-haspopup="listbox"
                    aria-expanded={jump_menu_open}
                >
                    {step + 1} / {steps.length}
                    <svg class="w-2.5 h-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
                    </svg>
                </button>
                {#if jump_menu_open}
                    <div
                        class="absolute top-full left-2 mt-1 bg-white border border-gray-200 rounded-md shadow-lg z-50 max-h-72 overflow-y-auto w-72"
                        role="listbox"
                    >
                        {#each steps as s, i}
                            <button
                                type="button"
                                onclick={() => jump_to(i)}
                                class="block w-full text-left px-3 py-1.5 text-xs hover:bg-indigo-50 {i === step ? 'bg-indigo-100 text-indigo-900 font-semibold' : 'text-gray-700'}"
                                role="option"
                                aria-selected={i === step}
                            >
                                <span class="text-gray-400 mr-2 tabular-nums">{i + 1}.</span>
                                {s.title}
                            </button>
                        {/each}
                    </div>
                {/if}
            </div>
            <div class="flex items-center gap-2">
                <span class="text-[10px] text-gray-500 whitespace-nowrap">
                    <kbd class="px-1.5 py-0.5 bg-white/70 border border-gray-300 rounded font-mono text-[10px]">Esc</kbd>
                    to close
                </span>
                <button
                    type="button"
                    onclick={close_and_remember}
                    class="text-gray-400 hover:text-gray-600 transition-colors p-1 rounded hover:bg-white/50"
                    aria-label="Close guide"
                >
                    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                </button>
            </div>
        </div>

        <div class="px-4 py-3 max-h-[60vh] overflow-y-auto">
            <h3 class="text-base font-semibold text-gray-900 mb-2">{current_step.title}</h3>
            <div class="text-sm text-gray-700 leading-relaxed">{@html current_step.body}</div>
        </div>

        <div class="px-4 py-2 bg-gray-50 border-t border-gray-200 rounded-b-lg flex items-center justify-end">
            <div class="flex gap-2">
                <button
                    type="button"
                    onclick={back}
                    disabled={is_first}
                    class="px-3 py-1 text-xs rounded border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
                >Back</button>
                <button
                    type="button"
                    onclick={next}
                    disabled={next_blocked}
                    class="inline-flex items-center gap-1 px-3 py-1 text-xs rounded bg-indigo-600 text-white font-medium hover:bg-indigo-700 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-indigo-600"
                >
                    {is_last ? 'Done' : 'Next →'}
                    <kbd class="px-1.5 py-0.5 bg-indigo-700/40 border border-indigo-300/40 rounded font-mono text-[10px] text-white/90">n</kbd>
                </button>
            </div>
        </div>
    </div>
{/if}
