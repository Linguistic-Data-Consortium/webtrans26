<script>
    // Floating bottom-right card that walks a first-time user through the
    // steps from docs/GETTING_STARTED.md. Auto-opens the first time; press
    // `g` (when no input/dialog has focus) to reopen later. Dismissal is
    // remembered in localStorage so it stays out of the way after that.
    //
    // Context-aware: subscribes to guide_state.guide_milestone. When other
    // components call `mark('something')`, the guide advances to the step
    // associated with that milestone (see milestone_step below).

    import { onMount } from 'svelte';
    import { guide_milestone } from './guide_state';

    // Bump the suffix whenever the guide content changes meaningfully —
    // that invalidates any previously-set "I've already seen the guide"
    // flag so a brand-new (or re-released) guide auto-opens for everyone
    // who hasn't dismissed THIS version. The per-user suffix is appended
    // below in `storage_key` once we have the user_id prop.
    const STORAGE_KEY_BASE = 'webtrans26_getting_started_dismissed_v2';
    let storage_key = $derived(`${STORAGE_KEY_BASE}_user_${user_id}`);
    const DEMO_AUDIO_URL = 'https://ldcresearch.s3.us-east-1.amazonaws.com/CarrieFisher.wav';

    // Only project managers see (and can opt into) the full setup walkthrough.
    // Everyone else gets the one-slide simple guide that just points them at
    // their next Action link.
    //
    // `user_id` is appended to the localStorage key so the dismissal flag is
    // tracked per user (rather than per browser). Two users sharing a
    // browser see each other's guide independently.
    let { project_manager = false, user_id = 'anon' } = $props();

    let open = $state(false);
    let step = $state(0);
    let full = $state(false); // false → just slide 0 (Welcome); true → all slides
    let copy_status = $state(''); // '', 'copied', 'failed'
    let jump_menu_open = $state(false);
    let jump_wrapper = $state(null); // bind:this on counter+dropdown — used for click-outside

    function jump_to(i) {
        step = i;
        jump_menu_open = false;
    }

    async function copy_to_clipboard(text) {
        try {
            await navigator.clipboard.writeText(text);
            copy_status = 'copied';
        } catch (e) {
            console.error('clipboard copy failed', e);
            copy_status = 'failed';
        }
        setTimeout(() => { copy_status = ''; }, 1500);
    }

    // Maps milestone names from guide_state.js → the step whose action they
    // SATISFY. When milestone X fires while the user is on step ≤ X, the
    // guide jumps to step X+1 (the next thing to do). If the user is
    // already past X, the milestone is a no-op — the guide doesn't slide
    // backwards.
    const milestone_step = {
        // 'start' is intentionally NOT in this map — it would otherwise
        // advance step 0 → 1 the moment the guide opens (because of the
        // `step <= target → step = target + 1` rule).
        //
        // Full mode steps:
        //   0  Open Projects                  11  Create a kit
        //   1  Create a project               12  Start transcribing
        //   2  Open the project               13  Ready to go (Action column)
        //   3  Open Project Tasks               (= the 1/1 slide in simple mode)
        //   4  Create a task
        //   5  Open the task
        //   6  Switch workflow
        //   7  Open Task Members
        //   8  Add yourself
        //   9  Open Kits
        //   10 (reserved — see step 10/11 split below)
        projects_tab_open: 0,         // step 0 done → step 1
        project_created: 1,           // step 1 done → step 2
        project_open: 2,              // step 2 done → step 3
        project_tasks_tab_open: 3,    // step 3 done → step 4
        task_created: 4,              // step 4 done → step 5
        task_open: 5,                 // step 5 done → step 6
        workflow_changed: 6,          // step 6 done → step 7
        task_members_tab_open: 7,     // step 7 done → step 8
        task_member_added: 8,         // step 8 done → step 9
        kits_tab_open: 9,             // step 9 done → step 10
        kit_created: 10,              // step 10 done → step 11
        work_started: 11              // step 11 done → step 12 (Ready to go)
    };
    // Track the latest milestone in local reactive state so $effect picks up
    // the change reliably (a bare store.subscribe at module init was
    // running but the assignment inside the closure didn't always wake up
    // Svelte's reactivity in this codebase).
    let current_milestone = $state('start');
    $effect(() => {
        const unsub = guide_milestone.subscribe((m) => {
            console.log('[guide] milestone update:', m);
            current_milestone = m;
        });
        return unsub;
    });
    $effect(() => {
        const target = milestone_step[current_milestone];
        // In simple (one-slide) mode we never auto-advance — the user only
        // sees Welcome. Milestones still update the store; they just don't
        // bump the visible step.
        if (!full) return;
        // Milestone names "step N is done" → advance to step N+1. Only fire
        // forward (skip if user is already past).
        if (target != null && step <= target) {
            step = target + 1;
        }
    });

    // Each step can optionally point at a DOM element by CSS selector
    // (`anchor`). When set, the guide card moves next to that element and a
    // pulsing ring highlights it. Without an anchor, the card falls back to
    // the bottom-right corner.
    //
    // Add `data-guide-target="name"` attributes on the elements you want
    // highlighted, then reference them as `[data-guide-target="name"]` here.
    const steps = [
        // 0 — projects_tab_open
        {
            title: '1. Open the Projects tab',
            body: `Click the highlighted <strong>Projects</strong> tab to start. Press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">h</kbd> any time for the keyboard cheat sheet. Full written walkthrough in the <a href="/documentation/GETTING_STARTED" class="text-indigo-600 underline">Getting Started doc</a>.`,
            anchor: '[data-guide-target="projects_tab"]'
        },
        // 1 — project_created
        {
            title: '2. Create a project',
            body: `Click <strong>Create Project</strong>, name it (e.g. <em>Demo</em>), and confirm.`,
            anchor: '[data-guide-target="create_project"]'
        },
        // 2 — project_open
        {
            title: "3. Open your new project",
            body: `Click the new project's row in the table to open its panel.`
        },
        // 3 — project_tasks_tab_open
        {
            title: '4. Open the task list',
            body: `Click the highlighted <strong>Open Task List</strong> button to jump into the project's tasks. (You can also use the <strong>Project Tasks</strong> tab inside the project panel.)`,
            anchor: '[data-guide-target="open_task_list"]'
        },
        // 4 — task_created
        {
            title: '5. Create a task',
            body: `Click <strong>Create Task</strong>, name it (e.g. <em>Demo Transcription</em>), and confirm.`,
            anchor: '[data-guide-target="create_task"]'
        },
        // 5 — task_open
        {
            title: "6. Open your new task",
            body: `Click the new task's row in the table to open its panel.`
        },
        // 6 — workflow_changed. The anchor selector lists two options
        // separated by a comma: before the user clicks Open Task Info, the
        // button is what's on-screen and gets highlighted. After they click
        // it, the button disappears and the workflow setting (inside Task
        // Info) is what's on-screen, and the guide moves there.
        {
            title: '7. Switch the workflow to Orderly',
            body: `Click <strong>Open Task Info</strong>, then change the workflow from <code class="px-1 bg-gray-100 rounded text-xs">OnTheFly</code> to <code class="px-1 bg-gray-100 rounded text-xs">Orderly</code>.`,
            anchor: '[data-guide-target="open_task_info"], [data-guide-target="task_workflow_setting"]'
        },
        // 7 — task_members_tab_open
        {
            title: '8. Open Task Members',
            body: `Click the highlighted <strong>Task Members</strong> tab.`,
            anchor: '[data-guide-target="task_members_tab"]'
        },
        // 8 — task_member_added
        {
            title: '9. Add yourself',
            body: `Click the highlighted <strong>Add Member</strong> button, type your name, and pick yourself from the list. (Add teammates here later the same way.)`,
            anchor: '[data-guide-target="add_task_member"]'
        },
        // 9 — kits_tab_open
        {
            title: '10. Open Kits',
            body: `Click the highlighted <strong>Kits</strong> tab.`,
            anchor: '[data-guide-target="kits_tab"]'
        },
        // 10 — kit_created. The audio URL is rendered out-of-band below the
        // body so the Copy button can wire onto it (Svelte handlers don't
        // work inside @html-rendered markup).
        {
            title: '11. Create a kit from the demo audio URL',
            body: `Click the highlighted <strong>Create Kits (Text Input)</strong> button, paste the demo URL below, click <strong>Parse</strong>, then <strong>Create</strong>.`,
            anchor: '[data-guide-target="create_kits_text"]',
            copyable: DEMO_AUDIO_URL
        },
        // 11 — work_started.
        {
            title: '12. Start transcribing',
            body: `Click the highlighted <strong>Work</strong> tab, then click the <strong>Action</strong> link for your new task. The waveform editor opens — press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">h</kbd> inside for the full cheat sheet.`,
            anchor: '[data-guide-target="work_tab"]'
        },
        // 12 — Ready to go. This is the wrap-up of the full guide AND the
        // 1/1 slide everyone sees in simple mode (visible_steps slices the
        // last entry off when full=false; see below).
        {
            title: 'Ready to go',
            body: `To start work on a task, click its link in the highlighted <strong>Action</strong> column. Press <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">h</kbd> for the keyboard cheat sheet, or <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px]">g</kbd> to reopen this guide. Full walkthrough in the <a href="/documentation/GETTING_STARTED" class="text-indigo-600 underline">Getting Started doc</a>.`,
            anchor: '[data-col="action"]'
        }
    ];

    // Anchor positioning state. While a step has an anchor, an interval
    // re-reads the element's rect ~10x/sec so the guide and ring follow it
    // through tab switches, scrolls, resizes, etc. When there's no anchor,
    // anchor_rect is null and the card falls back to bottom-right.
    let anchor_rect = $state(null);

    $effect(() => {
        if (!open) { anchor_rect = null; return; }
        const selector = current_step.anchor;
        if (!selector) { anchor_rect = null; return; }
        // The selector may be a comma-separated list of fallbacks. We try
        // each in order and use the LAST one that has any matches — that
        // way a later "post-click" target overrides an earlier
        // "click-this-first" target as soon as it appears. Each selector
        // uses querySelectorAll so multi-element targets (like a full
        // table column) collapse to a single union bounding box.
        const candidates = selector.split(',').map(s => s.trim()).filter(Boolean);
        const find = () => {
            let elements = [];
            for (const s of candidates) {
                const matches = Array.from(document.querySelectorAll(s));
                if (matches.length) elements = matches;
            }
            return elements;
        };
        const update = () => {
            const elements = find();
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
            // Store as a plain object so Svelte's reactivity sees changes.
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

    // Position the card adjacent to the anchor (below if there's room,
    // otherwise above). Clamps to the viewport so it stays visible.
    let card_style = $derived.by(() => {
        if (!anchor_rect) return 'bottom: 1rem; right: 1rem;';
        const card_w = 384;
        const est_h = 260;
        const margin = 12;
        let left = anchor_rect.left;
        const max_left = window.innerWidth - card_w - margin;
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
        // Clamp to viewport so the card never slips off-screen if the
        // anchor scrolls past either edge.
        if (top < margin) top = margin;
        const max_top = window.innerHeight - margin - 60;
        if (top > max_top) top = max_top;
        return `top: ${top}px; left: ${left}px;`;
    });

    // What the user can navigate through right now. Simple mode shows just
    // the LAST slide of `steps` (Ready to go / Action column) — that same
    // slide is also the wrap-up at the end of the full guide.
    let visible_steps = $derived(full ? steps : steps.slice(-1));
    let is_last = $derived(step >= visible_steps.length - 1);
    let is_first = $derived(step === 0);
    let current_step = $derived(visible_steps[step] || visible_steps[0]);

    function show() {
        // Reset the milestone so that a previous-session milestone (e.g. the
        // user clicked Projects earlier) doesn't immediately bump the guide
        // off step 0 again on manual reopen.
        guide_milestone.set('start');
        full = false;
        step = 0;
        open = true;
    }
    function switch_to_full() {
        full = true;
        step = 0;
    }
    function close_and_remember() {
        open = false;
        try { localStorage.setItem(storage_key, '1'); } catch (_) {}
    }
    function next() {
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
        if (input_focused()) return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        if (!open) {
            // Don't fight with PageKeyControls' own dialog-open check.
            if (document.querySelector('dialog[open]')) return;
            if (e.key === 'g') {
                e.preventDefault();
                show();
            }
            return;
        }
        // While the guide is open, claim the navigation keys.
        switch (e.key) {
            case 'Escape':
                e.preventDefault();
                // Escape closes the jump menu first, the guide second.
                if (jump_menu_open) jump_menu_open = false;
                else close_and_remember();
                break;
            case 'ArrowRight':
            case 'Enter':
            case 'n':
                e.preventDefault();
                next();
                break;
            case 'ArrowLeft':
                e.preventDefault();
                back();
                break;
        }
    }

    $effect(() => {
        window.addEventListener('keydown', on_keydown);
        return () => window.removeEventListener('keydown', on_keydown);
    });

    // Click outside the counter+dropdown closes the jump menu. Listener
    // is only active while the menu is open. Mousedown (capture) means we
    // run before the counter's own click handler, so toggling on the
    // counter itself still works (counter is inside jump_wrapper).
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
        let dismissed = false;
        try { dismissed = !!localStorage.getItem(storage_key); } catch (_) {}
        if (!dismissed) show();
    });
</script>

{#if open}
    {#if anchor_rect}
        <!-- Highlight ring around the current step's target. Solid indigo,
             no offset color, so it sits flush against the element regardless
             of the surrounding background (bg-muted tabs, white cards, etc). -->
        <div
            class="fixed pointer-events-none z-30 rounded-md ring-4 ring-indigo-500 animate-pulse"
            style="left: {anchor_rect.left}px; top: {anchor_rect.top}px; width: {anchor_rect.width}px; height: {anchor_rect.height}px;"
        ></div>
    {/if}

    <div
        class="fixed z-40 w-[24rem] max-w-[calc(100vw-2rem)] bg-white border border-gray-200 rounded-lg shadow-xl transition-[top,left] duration-200"
        style={card_style}
        role="dialog"
        aria-label="Getting started guide"
    >
        <div class="relative px-4 py-2 bg-gradient-to-r from-indigo-50 via-purple-50 to-pink-50 border-b border-gray-200 rounded-t-lg flex items-center justify-between">
            <!-- The wrapper is what the click-outside handler keys off —
                 clicks inside it (counter, dropdown, items) don't close
                 the menu. The dropdown itself is positioned relative to
                 the header (which has `relative`) so it sits against the
                 card's left edge, not under the counter. -->
            <div class="flex items-center gap-2" bind:this={jump_wrapper}>
                <span class="text-xs font-semibold uppercase tracking-wide text-gray-600">Getting started</span>
                <button
                    type="button"
                    onclick={() => jump_menu_open = !jump_menu_open}
                    class="text-[10px] text-gray-500 hover:text-gray-800 cursor-pointer inline-flex items-center gap-0.5"
                    aria-haspopup="listbox"
                    aria-expanded={jump_menu_open}
                >
                    {step + 1} / {visible_steps.length}
                    <svg class="w-2.5 h-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
                    </svg>
                </button>
                {#if jump_menu_open}
                    <div
                        class="absolute top-full left-2 mt-1 bg-white border border-gray-200 rounded-md shadow-lg z-50 max-h-72 overflow-y-auto w-72"
                        role="listbox"
                    >
                        {#each visible_steps as s, i}
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

        <div class="px-4 py-3 max-h-[60vh] overflow-y-auto">
            <h3 class="text-base font-semibold text-gray-900 mb-2">{current_step.title}</h3>
            <div class="text-sm text-gray-700 leading-relaxed">{@html current_step.body}</div>
            {#if current_step.copyable}
                <div class="mt-2 flex items-stretch gap-2">
                    <code class="flex-1 min-w-0 px-2 py-1.5 bg-gray-100 rounded text-[11px] font-mono break-all">{current_step.copyable}</code>
                    <button
                        type="button"
                        onclick={() => copy_to_clipboard(current_step.copyable)}
                        class="shrink-0 px-2 rounded border border-gray-300 bg-white text-xs hover:bg-gray-50 font-medium text-gray-700"
                    >
                        {#if copy_status === 'copied'}
                            ✓ Copied
                        {:else if copy_status === 'failed'}
                            ⚠ Failed
                        {:else}
                            Copy
                        {/if}
                    </button>
                </div>
            {/if}
        </div>

        <div class="px-4 py-2 bg-gray-50 border-t border-gray-200 rounded-b-lg flex items-center justify-between">
            <div class="flex flex-col items-start gap-0.5">
                <button
                    type="button"
                    onclick={close_and_remember}
                    class="text-xs text-gray-500 hover:text-gray-700"
                >Skip guide</button>
                {#if project_manager && !full}
                    <button
                        type="button"
                        onclick={switch_to_full}
                        class="text-[11px] text-indigo-600 hover:text-indigo-800 underline"
                    >Switch to full setup guide</button>
                {/if}
            </div>
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
                    class="inline-flex items-center gap-1 px-3 py-1 text-xs rounded bg-indigo-600 text-white font-medium hover:bg-indigo-700"
                >
                    {is_last ? 'Done' : 'Next →'}
                    <kbd class="px-1.5 py-0.5 bg-indigo-700/40 border border-indigo-300/40 rounded font-mono text-[10px] text-white/90">n</kbd>
                </button>
            </div>
        </div>
    </div>
{/if}
