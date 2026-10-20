<script>
    // Which stretch of audio an ASR run is allowed to fill.
    //
    // Every ASR service returns spans for the whole recording. On a long file
    // that is thousands of segments, and usually only one part is wanted — so
    // this asks first, and asr.svelte.js keeps only the spans that fit inside
    // what is asked for.
    //
    // Prefilled from the waveform selection when there is one, since "run ASR
    // over what I just selected" is the common case. Otherwise both fields
    // start empty: a blank begin means the start of the recording and a blank
    // end means its end, so submitting as-is runs over the whole thing.
    import BaseDialog from './BaseDialog.svelte';
    import { btn, cbtn } from '../../work/buttons';
    import { activeo } from '../shared.svelte';
    import { round_to_3_places } from '../times';

    let {
        dialogRef = $bindable(),
        onRun,
        onCancel = null
    } = $props();

    let beg_value = $state('');
    let end_value = $state('');
    let error = $state(null);
    let input_el;

    // Called by the parent just before showModal(), so the fields track the
    // selection as it is at that moment rather than when this first rendered.
    export function prefill_from_selection(){
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
    }

    function parsed(){
        const beg = beg_value.trim() === '' ? 0 : Number(beg_value);
        // Blank end is deliberate: it means "however long the recording is",
        // which the caller can't know here and doesn't need to.
        const end = end_value.trim() === '' ? Infinity : Number(end_value);
        if(Number.isNaN(beg) || Number.isNaN(end)) return { error: 'those need to be numbers of seconds' };
        if(beg < 0)                                return { error: "a span can't start before zero" };
        if(end <= beg)                             return { error: 'the end has to come after the beginning' };
        return { span: { beg, end } };
    }

    function run(){
        const x = parsed();
        if(x.error){ error = x.error; return; }
        error = null;
        dialogRef.close();
        onRun(x.span);
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
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-lg" title="Run ASR over which stretch?" showClose={false}>
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="p-6" onkeydown={onKeydown}>
            <p class="text-sm text-gray-600 mb-4">
                Only segments that fit entirely inside this span are added.
                Leave a field blank for the start or the end of the recording.
            </p>

            <div class="flex items-end gap-3">
                <label class="flex-1 text-sm">
                    <span class="block text-gray-700 mb-1">Begin (seconds)</span>
                    <input
                        bind:this={input_el}
                        use:focus
                        bind:value={beg_value}
                        type="text"
                        inputmode="decimal"
                        placeholder="start of recording"
                        class="w-full px-2 py-1 border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
                    />
                </label>
                <label class="flex-1 text-sm">
                    <span class="block text-gray-700 mb-1">End (seconds)</span>
                    <input
                        bind:value={end_value}
                        type="text"
                        inputmode="decimal"
                        placeholder="end of recording"
                        class="w-full px-2 py-1 border border-gray-300 rounded focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
                    />
                </label>
            </div>

            {#if error}
                <div class="mt-3 text-sm text-red-600">{error}</div>
            {/if}

            <div class="mt-6 flex justify-end gap-2">
                <button type="button" class={btn} onclick={cancel}>Cancel</button>
                <button type="button" class={cbtn} onclick={run}>Run ASR</button>
            </div>

            <p class="mt-4 text-xs text-gray-500">
                <kbd class="px-1.5 py-0.5 bg-gray-100 rounded font-mono">Enter</kbd> to run,
                <kbd class="px-1.5 py-0.5 bg-gray-100 rounded font-mono">Esc</kbd> to cancel.
            </p>
        </div>
    {/snippet}
</BaseDialog>
