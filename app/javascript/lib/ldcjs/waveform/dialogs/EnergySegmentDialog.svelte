<script>
    // The settings for a segments-from-sound-level run, asked for each time.
    //
    // The noise floor is measured from the recording itself; what's asked here
    // is how far above it counts as sound, and how the stretches found are
    // shaped into segments. Prefilled from the last run in this browser, or
    // from energy_segments.js's DEFAULTS. The stretch of audio is prefilled
    // from the waveform selection, as the ASR span dialog does — blank means
    // the whole recording.
    import BaseDialog from './BaseDialog.svelte';
    import { btn, cbtn } from '../../work/buttons';
    import { activeo } from '../shared.svelte';
    import { round_to_3_places } from '../times';
    import { DEFAULTS, LABELS, parse_params, remembered_params, SETTINGS_KEY } from '../energy_segments';

    // onPreview, when given, offers a second way out: the same settings run
    // as a preview layer (energy_preview.js), shown under the waveform and
    // saved as nothing.
    let {
        dialogRef = $bindable(),
        onRun,
        onPreview = null,
        onCancel = null
    } = $props();

    const KEYS = Object.keys(DEFAULTS);

    let beg_value = $state('');
    let end_value = $state('');
    let fields = $state(as_fields(DEFAULTS));
    let error = $state(null);

    function as_fields(p){
        const f = {};
        for(const k of KEYS) f[k] = p[k] == null ? '' : String(p[k]);
        return f;
    }

    function remember(p){
        try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(p)); } catch(e){}
    }

    // Called by the parent just before showModal().
    export function prefill(){
        const offset = activeo.wave_selection_offset;
        const length = activeo.wave_selection_length;
        error = null;
        if(offset != null && length > 0){
            beg_value = String(round_to_3_places(offset));
            end_value = String(round_to_3_places(offset + length));
        }
        else{
            beg_value = '';
            end_value = '';
        }
        fields = as_fields(remembered_params());
    }

    function parsed_span(){
        const beg = beg_value.trim() === '' ? 0 : Number(beg_value);
        const end = end_value.trim() === '' ? Infinity : Number(end_value);
        if(Number.isNaN(beg) || Number.isNaN(end)) return { error: 'the stretch needs numbers of seconds' };
        if(beg < 0)                                return { error: "the stretch can't start before zero" };
        if(end <= beg)                             return { error: 'the end has to come after the beginning' };
        return { span: { beg, end } };
    }

    function run(preview = false){
        const s = parsed_span();
        if(s.error){ error = s.error; return; }
        const p = parse_params(fields);
        if(p.error){ error = p.error; return; }
        error = null;
        remember(p.params);
        dialogRef.close();
        (preview ? onPreview : onRun)(s.span, p.params);
    }

    function reset(){
        fields = as_fields(DEFAULTS);
    }

    function cancel(){
        dialogRef.close();
        onCancel?.();
    }

    function onKeydown(e){
        if(e.key === 'Enter'){ e.preventDefault(); e.stopPropagation(); run(); }
        else if(e.key === 'Escape'){ e.preventDefault(); e.stopPropagation(); cancel(); }
        else e.stopPropagation(); // digits are menu shortcuts elsewhere; not here
    }

    function focus(x){ setTimeout( () => x.focus(), 50 ); }

    const input = "w-full px-2 py-1 border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500";
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-xl" title="Segments from sound level" showClose={false}>
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="p-6" onkeydown={onKeydown} data-testid="energy-dialog">
            <p class="text-sm text-gray-600 mb-4">
                Adds an empty segment wherever the sound rises above the
                recording's background level, skipping anything that would
                overlap a segment already there. Preview shows what it would
                find, under the waveform, without adding anything.
            </p>

            <div class="flex items-end gap-3">
                <label class="flex-1 text-sm">
                    <span class="block text-gray-700 mb-1">Begin (seconds)</span>
                    <input use:focus bind:value={beg_value} type="text" inputmode="decimal"
                           placeholder="start of recording" class={input} data-testid="energy-beg" />
                </label>
                <label class="flex-1 text-sm">
                    <span class="block text-gray-700 mb-1">End (seconds)</span>
                    <input bind:value={end_value} type="text" inputmode="decimal"
                           placeholder="end of recording" class={input} data-testid="energy-end" />
                </label>
            </div>

            <div class="mt-4 grid grid-cols-1 sm:grid-cols-2 gap-3">
                {#each KEYS as k}
                    <label class="text-sm">
                        <span class="block text-gray-700 mb-1">{LABELS[k]}</span>
                        <input bind:value={fields[k]} type="text" inputmode="decimal"
                               placeholder={k == 'max_segment' ? 'no limit' : k == 'max_sound_spread' ? 'off' : String(DEFAULTS[k])}
                               class={input} data-testid={`energy-${k}`} />
                    </label>
                {/each}
            </div>

            {#if error}
                <div class="mt-3 text-sm text-red-600" role="alert">{error}</div>
            {/if}

            <div class="mt-6 flex justify-between gap-2">
                <button type="button" class={btn} onclick={reset}>Defaults</button>
                <div class="flex gap-2">
                    <button type="button" class={btn} onclick={cancel}>Cancel</button>
                    {#if onPreview}
                        <button type="button" class={btn} onclick={() => run(true)} data-testid="energy-preview"
                                title="Show what these settings find under the waveform, without adding segments">Preview</button>
                    {/if}
                    <button type="button" class={cbtn} onclick={() => run()} data-testid="energy-run">Find segments</button>
                </div>
            </div>

            <p class="mt-4 text-xs text-gray-500">
                <kbd class="px-1.5 py-0.5 bg-gray-100 rounded font-mono">Enter</kbd> to run,
                <kbd class="px-1.5 py-0.5 bg-gray-100 rounded font-mono">Esc</kbd> to cancel.
                A higher margin finds less; a longer pause joins more.
            </p>
        </div>
    {/snippet}
</BaseDialog>
