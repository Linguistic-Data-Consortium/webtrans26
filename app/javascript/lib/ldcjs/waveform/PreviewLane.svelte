<script>
    // Span layers under the waveform (span_layers.svelte.js): a bar per
    // layer — per channel, when a layer covers more than one — with its spans
    // drawn where they fall in the window. Nothing here is an annotation.
    //
    // Click a span to select it on the waveform (so it can be heard), then
    // add it alone; or add a whole layer. Either way only gaps are filled.
    import { onMount } from 'svelte';
    import { toast } from 'svelte-sonner';
    import { Eye, EyeOff, X } from '@lucide/svelte';
    import { btn, cbtn } from '../work/buttons';
    import { activeo } from './shared.svelte';
    import { span_layers, load_previews, update_layer, remove_layer, select_span, selected_span } from './span_layers.svelte';
    import { bands_in_window, by_channel } from './span_geometry';
    import { add_spans_as_segments } from './span_promote';
    import { display_docid } from './helpers';

    let { width, kit_id, docids, set_current_selection, play_current_span = null } = $props();

    onMount( () => { load_previews(kit_id); } );

    let busy = $state(false);

    function pick(layer, i){
        const s = layer.segments[i];
        select_span(layer.id, i);
        set_current_selection(s.beg, s.end - s.beg);
    }

    async function add(spans, what){
        busy = true;
        try {
            const { added, skipped } = await add_spans_as_segments(spans);
            const extra = skipped ? `; ${skipped} skipped because ${skipped == 1 ? 'it overlaps' : 'they overlap'} existing segments` : '';
            (added ? toast.success : toast.info)(`${added} ${added == 1 ? 'segment' : 'segments'} added from ${what}${extra}.`);
        }
        finally {
            busy = false;
        }
    }

    const sel = $derived(selected_span());
    const fmt = (t) => t.toFixed(3);
</script>

{#if span_layers.layers.length}
<div class="mt-1 mb-2 text-xs" style="width: {width}px" data-testid="preview-lane">
    <div class="text-gray-500 mb-0.5">Preview — not saved as annotations</div>
    {#each span_layers.layers as layer (layer.id)}
        <div class="flex items-center gap-2 mt-1" data-testid="preview-layer">
            <span class="inline-block w-3 h-3 rounded-sm shrink-0" style="background: {layer.color}"></span>
            <span class="truncate text-gray-800" title={layer.note ? `${layer.label} — ${layer.note}` : layer.label}>{layer.label}</span>
            <span class="text-gray-500 shrink-0">{layer.segments.length} span{layer.segments.length == 1 ? '' : 's'}</span>
            <span class="ml-auto flex gap-1 shrink-0">
                <button type="button" class="px-1 text-gray-600 hover:text-gray-900"
                        onclick={() => update_layer(layer.id, { visible: !layer.visible })}
                        title={layer.visible ? 'Hide' : 'Show'} data-testid="preview-toggle">
                    {#if layer.visible}<Eye size=14 />{:else}<EyeOff size=14 />{/if}
                </button>
                <button type="button" class="{cbtn} !py-0 !px-2 text-xs" disabled={busy}
                        onclick={() => add(layer.segments, 'the preview')} data-testid="preview-add-all">Add as segments</button>
                <button type="button" class="px-1 text-gray-600 hover:text-red-700" onclick={() => remove_layer(layer.id)}
                        title="Remove this preview" data-testid="preview-remove"><X size=14 /></button>
            </span>
        </div>
        {#if layer.visible}
            {#each by_channel(layer.segments, docids) as ch (ch.docid)}
                <div class="relative h-3 bg-gray-100 rounded-sm" title={by_channel(layer.segments, docids).length > 1 ? display_docid(ch.docid) : ''}>
                    {#each bands_in_window(ch.segments, activeo.wave_display_offset, activeo.wave_display_length, width) as b (b.i)}
                        {@const s = ch.segments[b.i]}
                        <button type="button" aria-label="preview span {fmt(s.beg)}–{fmt(s.end)}"
                                class="absolute top-0 h-full rounded-sm {span_layers.selected?.layer === layer.id && span_layers.selected?.i === s.i ? 'ring-2 ring-offset-1 ring-gray-900' : ''}"
                                style="left: {b.left}px; width: {b.width}px; background: {layer.color}; opacity: 0.75"
                                title="{fmt(s.beg)}–{fmt(s.end)}{s.text ? ` · ${s.text}` : ''}"
                                onclick={() => pick(layer, s.i)}
                                data-testid="preview-span" data-beg={s.beg} data-end={s.end}></button>
                    {/each}
                </div>
            {/each}
        {/if}
    {/each}
    {#if sel}
        <div class="flex items-center gap-2 mt-1" data-testid="preview-selected">
            <span class="text-gray-700">Selected: {fmt(sel.span.beg)}–{fmt(sel.span.end)} s{sel.span.text ? ` · ${sel.span.text}` : ''}</span>
            {#if play_current_span}
                <button type="button" class="{btn} !py-0 !px-2 text-xs" onclick={() => play_current_span()}>Play</button>
            {/if}
            <button type="button" class="{cbtn} !py-0 !px-2 text-xs" disabled={busy}
                    onclick={() => add([ sel.span ], 'the selected span')} data-testid="preview-add-one">Add as a segment</button>
            <button type="button" class="px-1 text-gray-600" onclick={() => span_layers.selected = null} title="Deselect"><X size=14 /></button>
        </div>
    {/if}
</div>
{/if}
