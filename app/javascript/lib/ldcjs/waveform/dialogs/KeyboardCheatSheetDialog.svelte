<script>
    import BaseDialog from './BaseDialog.svelte';
    import { waveform_map, modifier_label, modes } from '../bindings';
    import { settings } from '../stores';

    let {
        dialogRef = $bindable(),
        onKeydown: parentOnKeydown = null
    } = $props();

    // Which keymap the keyboard is rendering (cursor / window / selection).
    // beg & end share the selection keymap, so this is the right grouping.
    let view_mode = $state('cursor');
    let current_modifier = $state('ctrl');
    settings.subscribe(s => current_modifier = s.modifier || 'ctrl');
    let mod_label = $derived(modifier_label(current_modifier));

    // Tabs: shown in the same colors as the mode banner / list cheat sheet,
    // so users associate "this color = cursor mode" everywhere.
    const tabs = [
        { id: 'cursor',    name: 'Cursor',    bg: 'bg-red-100',     text: 'text-red-900',     ring: 'ring-red-400' },
        { id: 'window',    name: 'Window',    bg: 'bg-blue-100',    text: 'text-blue-900',    ring: 'ring-blue-400' },
        { id: 'selection', name: 'Selection', bg: 'bg-emerald-100', text: 'text-emerald-900', ring: 'ring-emerald-400' }
    ];

    // Physical QWERTY layout. `look` is the key string the keymap uses;
    // `null` means a modifier/structural key we don't bind directly.
    // `w` is the key width in units (1 ≈ a standard letter key).
    const layout = [
        [
            { label: '`', look: '`',  w: 1 },
            { label: '1', look: '1',  w: 1 }, { label: '2', look: '2', w: 1 },
            { label: '3', look: '3',  w: 1 }, { label: '4', look: '4', w: 1 },
            { label: '5', look: '5',  w: 1 }, { label: '6', look: '6', w: 1 },
            { label: '7', look: '7',  w: 1 }, { label: '8', look: '8', w: 1 },
            { label: '9', look: '9',  w: 1 }, { label: '0', look: '0', w: 1 },
            { label: '-', look: '-',  w: 1 }, { label: '=', look: '=', w: 1 },
            { label: 'backspace', look: null, w: 2 }
        ],
        [
            { label: 'tab', look: 'Tab', w: 1.5 },
            { label: 'Q', look: 'q', w: 1 }, { label: 'W', look: 'w', w: 1 },
            { label: 'E', look: 'e', w: 1 }, { label: 'R', look: 'r', w: 1 },
            { label: 'T', look: 't', w: 1 }, { label: 'Y', look: 'y', w: 1 },
            { label: 'U', look: 'u', w: 1 }, { label: 'I', look: 'i', w: 1 },
            { label: 'O', look: 'o', w: 1 }, { label: 'P', look: 'p', w: 1 },
            { label: '[', look: '[', w: 1 }, { label: ']', look: ']', w: 1 },
            { label: '\\', look: '\\', w: 1.5 }
        ],
        [
            { label: 'esc', look: 'Escape', w: 1.75 },
            { label: 'A', look: 'a', w: 1 }, { label: 'S', look: 's', w: 1 },
            { label: 'D', look: 'd', w: 1 }, { label: 'F', look: 'f', w: 1 },
            { label: 'G', look: 'g', w: 1 }, { label: 'H', look: 'h', w: 1 },
            { label: 'J', look: 'j', w: 1 }, { label: 'K', look: 'k', w: 1 },
            { label: 'L', look: 'l', w: 1 }, { label: ';', look: ';', w: 1 },
            { label: "'", look: "'", w: 1 },
            { label: 'enter', look: 'Enter', w: 2 }
        ],
        [
            { label: 'shift', look: null, w: 2.25 },
            { label: 'Z', look: 'z', w: 1 }, { label: 'X', look: 'x', w: 1 },
            { label: 'C', look: 'c', w: 1 }, { label: 'V', look: 'v', w: 1 },
            { label: 'B', look: 'b', w: 1 }, { label: 'N', look: 'n', w: 1 },
            { label: 'M', look: 'm', w: 1 }, { label: ',', look: ',', w: 1 },
            { label: '.', look: '.', w: 1 }, { label: '/', look: '/', w: 1 },
            { label: 'shift', look: null, w: 2.75 }
        ],
        [
            { label: 'ctrl', look: null, w: 1.5 },
            { label: 'alt',  look: null, w: 1.25 },
            { label: 'cmd',  look: null, w: 1.25 },
            { label: 'space', look: ' ', w: 6 },
            { label: 'cmd',  look: null, w: 1.25 },
            { label: 'alt',  look: null, w: 1.25 },
            { label: '←', look: 'ArrowLeft',  w: 1 },
            { label: '↑', look: 'ArrowUp',    w: 1 },
            { label: '↓', look: 'ArrowDown',  w: 1 },
            { label: '→', look: 'ArrowRight', w: 1 }
        ]
    ];

    function lookup(map, look){
        if (look == null) return null;
        const v = map?.[look];
        return v && typeof v === 'object' ? v : null;
    }
    function bg_for(b){
        if (!b) return 'bg-white border-gray-200 text-gray-400';
        if (b.group === 'home')   return 'bg-amber-100 border-amber-300 text-amber-900';
        if (b.group === 'mode')   return 'bg-indigo-100 border-indigo-300 text-indigo-900';
        if (b.group === 'global') return 'bg-emerald-50 border-emerald-200 text-emerald-900';
        if (b.group === 'system') return 'bg-slate-100 border-slate-300 text-slate-700';
        return 'bg-white border-gray-200';
    }

    let map = $derived(waveform_map[view_mode] || {});
    let ctrl_map = $derived(waveform_map.control?.[view_mode] || {});

    // Bindings that need a modifier — shown separately below the keyboard.
    let mod_bindings = $derived(
        Object.entries(ctrl_map)
            .filter(([k, v]) => typeof v === 'object' && v.desc)
            .map(([k, v]) => ({ key: v.label ?? k, desc: v.desc }))
    );
    // Uppercase (shifted) bindings — usually a separate action from the
    // lowercase letter. Shown so they aren't lost in the keyboard view.
    let shifted_bindings = $derived(
        Object.entries(map)
            .filter(([k, v]) => k.length === 1 && k !== k.toLowerCase()
                                && typeof v === 'object' && v.desc)
            .map(([k, v]) => ({ key: k, desc: v.desc }))
    );

    function focus(x) { x.focus(); }
    function onKeydown(e){
        // Mode-switch keys jump between cursor/window/selection views without
        // closing the dialog.
        switch (e.key) {
            case 'c': view_mode = 'cursor';    return;
            case 'w': view_mode = 'window';    return;
            case 'b':
            case 'e':
            case 's': view_mode = 'selection'; return;
            case 'Escape':
            case 'q':
                dialogRef.close();
                if (parentOnKeydown) parentOnKeydown(e);
                return;
        }
        dialogRef.close();
        if (parentOnKeydown) parentOnKeydown(e);
    }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="w-[96vw] max-w-none !max-h-[96vh]" title="Keyboard Layout" {onKeydown} showClose={false}>
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div use:focus tabindex="0" onkeydown={onKeydown} class="p-5 h-[calc(96vh-4rem)] overflow-auto outline-none text-sm">
            <div class="bg-amber-50 border border-amber-200 rounded p-2 mb-4 flex items-center gap-3 text-xs">
                <span class="text-amber-900">Each key shows what it does in the selected mode.</span>
                <span class="text-amber-900">Press <kbd class="px-1.5 py-0.5 bg-white rounded font-mono shadow-sm">c</kbd>/<kbd class="px-1.5 py-0.5 bg-white rounded font-mono shadow-sm">w</kbd>/<kbd class="px-1.5 py-0.5 bg-white rounded font-mono shadow-sm">b</kbd>/<kbd class="px-1.5 py-0.5 bg-white rounded font-mono shadow-sm">e</kbd> to switch view.</span>
                <span class="ml-auto text-amber-700">Press any other key to dismiss.</span>
            </div>

            <!-- Mode tabs -->
            <div class="flex gap-2 mb-4">
                {#each tabs as t}
                    {@const active = view_mode === t.id}
                    <button
                        type="button"
                        onclick={() => view_mode = t.id}
                        class="px-3 py-1.5 rounded border text-xs font-semibold transition-colors {active ? `${t.bg} ${t.text} border-current ring-2 ring-offset-1 ${t.ring}` : 'bg-white text-gray-600 border-gray-200 hover:border-gray-400'}"
                    >
                        {t.name}
                    </button>
                {/each}
            </div>

            <!-- Color legend -->
            <div class="flex flex-wrap items-center gap-3 mb-3 text-[11px] text-gray-600">
                <div class="flex items-center gap-1.5"><span class="w-3 h-3 rounded bg-amber-100 border border-amber-300"></span>home key</div>
                <div class="flex items-center gap-1.5"><span class="w-3 h-3 rounded bg-indigo-100 border border-indigo-300"></span>mode switch</div>
                <div class="flex items-center gap-1.5"><span class="w-3 h-3 rounded bg-emerald-50 border border-emerald-200"></span>command</div>
                <div class="flex items-center gap-1.5"><span class="w-3 h-3 rounded bg-slate-100 border border-slate-300"></span>system</div>
                <div class="flex items-center gap-1.5"><span class="w-3 h-3 rounded bg-white border border-gray-200"></span>unbound</div>
            </div>

            <!-- Keyboard rows -->
            <div class="space-y-1 select-none">
                {#each layout as row}
                    <div class="flex gap-1">
                        {#each row as k}
                            {@const b = lookup(map, k.look)}
                            <div
                                class="flex flex-col items-stretch p-1 rounded border overflow-hidden font-mono {bg_for(b)}"
                                style="width: {k.w * 3.4}rem; height: 3.4rem;"
                            >
                                <div class="text-xs font-bold leading-none">{k.label}</div>
                                {#if b}
                                    <div class="text-[9px] leading-tight mt-auto opacity-80 line-clamp-3 font-sans">{b.desc}</div>
                                {/if}
                            </div>
                        {/each}
                    </div>
                {/each}
            </div>

            <!-- Bindings that aren't on the unmodified key -->
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-5">
                {#if shifted_bindings.length}
                    <div>
                        <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">Shifted</h3>
                        <div class="space-y-1">
                            {#each shifted_bindings as b}
                                <div class="flex items-center p-1.5 bg-gray-50 rounded">
                                    <kbd class="px-1.5 py-0.5 bg-white border border-gray-300 rounded font-mono text-xs mr-2 min-w-[60px] text-center">shift-{b.key.toLowerCase()}</kbd>
                                    <span class="text-gray-700 text-xs">{b.desc}</span>
                                </div>
                            {/each}
                        </div>
                    </div>
                {/if}

                {#if mod_bindings.length}
                    <div>
                        <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">{mod_label}-modified</h3>
                        <div class="space-y-1">
                            {#each mod_bindings as b}
                                <div class="flex items-center p-1.5 bg-gray-50 rounded">
                                    <kbd class="px-1.5 py-0.5 bg-white border border-gray-300 rounded font-mono text-xs mr-2 min-w-[80px] text-center">{mod_label}-{b.key}</kbd>
                                    <span class="text-gray-700 text-xs">{b.desc}</span>
                                </div>
                            {/each}
                        </div>
                    </div>
                {/if}
            </div>
        </div>
    {/snippet}
</BaseDialog>
