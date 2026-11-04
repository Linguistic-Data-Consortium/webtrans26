<script>
    // Statistics on the waveform selection: its level, peak and the quartiles
    // of its 20 ms frame levels, per channel — the frames and dB scale the
    // sound-level segmentation uses (energy_segments.js's selection_stats).
    // For experimenting: what does speech measure here, what does the room?
    import BaseDialog from './BaseDialog.svelte';
    import { btn } from '../../work/buttons';
    import { display_docid } from '../helpers';
    import { round_to_3_places } from '../times';

    let { dialogRef = $bindable() } = $props();

    let span = $state(null);
    let rows = $state(null);
    let error = $state(null);
    let copied = $state(false);

    // `run` resolves with the rows. Shown at once, filled when they arrive.
    // `settings` are the sound-level settings the run side was measured with.
    export function show(selection, run, settings = null){
        span = selection;
        margin = settings?.margin_db ?? null;
        rows = null;
        error = null;
        copied = false;
        dialogRef.showModal();
        run().then( (r) => rows = r, (e) => error = e?.message || String(e) );
    }

    const db = (x) => x == null ? '–' : x.toFixed(1);
    const LINES = [
        [ 'Duration (s)',      (r) => r.duration.toFixed(3) ],
        [ 'Frames (20 ms)',    (r) => String(r.frames) ],
        [ 'Level, RMS (dBFS)', (r) => db(r.rms_db) ],
        [ 'Peak (dBFS)',       (r) => db(r.peak_db) ],
        [ 'Frame level: min',  (r) => db(r.min) ],
        [ 'Q1',                (r) => db(r.q1) ],
        [ 'Median',            (r) => db(r.median) ],
        [ 'Q3',                (r) => db(r.q3) ],
        [ 'Max',               (r) => db(r.max) ],
        [ 'Silent frames',     (r) => String(r.silent) ],
        // What a sound-level run would make of it (energy_segments.js).
        [ 'Background floor (dBFS)', (r) => db(r.floor_db) ],
        [ 'Threshold (dBFS)',        (r) => db(r.threshold_db) ],
        [ 'Sound: share of frames',  (r) => r.sound_share == null ? '–' : `${Math.round(100 * r.sound_share)}%` ],
        [ 'Sound: spread, Q3−Q1 (dB)', (r) => db(r.sound_spread) ]
    ];

    let margin = $state(null);

    // Tab-separated, for a spreadsheet.
    async function copy(){
        const head = [ `${round_to_3_places(span.beg)}–${round_to_3_places(span.end)} s`, ...rows.map( (r) => r.docid ) ].join('\t');
        const body = LINES.map( ([ label, f ]) => [ label, ...rows.map(f) ].join('\t') ).join('\n');
        try {
            await navigator.clipboard.writeText(`${head}\n${body}\n`);
            copied = true;
        }
        catch(e){
            error = `Couldn't copy: ${e?.message || e}`;
        }
    }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-2xl" title="Selection statistics">
    {#snippet children({ dialog })}
        <div class="p-6 text-sm" data-testid="stats-dialog">
            {#if span}
                <p class="text-gray-700 mb-3">
                    {round_to_3_places(span.beg)}–{round_to_3_places(span.end)} s
                </p>
            {/if}
            {#if error}
                <p class="text-red-700" role="alert">{error}</p>
            {:else if !rows}
                <p class="text-gray-600">Measuring…</p>
            {:else}
                <div class="overflow-x-auto">
                    <table class="w-full tabular-nums" data-testid="stats-table">
                        {#if rows.length > 1}
                            <thead>
                                <tr><th></th>{#each rows as r}<th class="text-right px-2 font-normal text-gray-600 truncate max-w-40" title={r.docid}>{display_docid(r.docid)}</th>{/each}</tr>
                            </thead>
                        {/if}
                        <tbody>
                            {#each LINES as [ label, f ]}
                                <tr class="border-t border-gray-100">
                                    <td class="py-1 pr-4 text-gray-700">{label}</td>
                                    {#each rows as r}<td class="py-1 px-2 text-right" data-testid={`stats-${label}`}>{f(r)}</td>{/each}
                                </tr>
                            {/each}
                        </tbody>
                    </table>
                </div>
                <p class="mt-3 text-xs text-gray-500">
                    Levels are dBFS: 0 is full scale, so a full-scale sine measures −3 RMS.
                    Frame levels are the RMS of each whole 20 ms frame, counted from the
                    start of the selection; quartiles interpolate between ranks. Silent
                    frames are at or below −90 dB.
                </p>
                <p class="mt-2 text-xs text-gray-500">
                    The last four are what Segments from sound level would make of this
                    stretch, with the settings last used here{margin != null ? ` (margin ${margin} dB)` : ''}:
                    the background measured over at least a minute around it, and how
                    much of the selection is sound — at or above the threshold less 3 dB —
                    and how spread that sound is. A segment needs enough sound to be kept
                    (the "least of a segment that is sound" setting), and, if a spread
                    limit is set, no more spread than that.
                </p>
                <div class="mt-3 flex items-center gap-2">
                    <button type="button" class={btn} onclick={copy} data-testid="stats-copy">Copy as table</button>
                    {#if copied}<span class="text-green-700 text-xs">Copied.</span>{/if}
                </div>
            {/if}
        </div>
    {/snippet}
</BaseDialog>
