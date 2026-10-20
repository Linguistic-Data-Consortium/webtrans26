<script>
    import BaseDialog from './BaseDialog.svelte';
    import { modifiers } from '../bindings';

    let {
        dialogRef = $bindable(),
        settingsArray = [],
        settingsHash = {},
        currentModifier = 'ctrl',
        onSelectModifier = () => {},
        onKeydown = null
    } = $props();

    function focus(x) { x.focus(); }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-3xl" title="Settings" {onKeydown} showClose={false}>
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div use:focus tabindex="0" onkeydown={onKeydown} class="p-5 outline-none text-sm">
            <div class="bg-amber-50 border border-amber-200 rounded p-2 mb-4 flex items-center gap-3 text-xs">
                <span class="text-amber-900">Press the highlighted key to toggle a setting.</span>
                <span class="ml-auto text-amber-700">Press <kbd class="px-1.5 py-0.5 bg-white rounded font-mono shadow-sm">q</kbd> to close.</span>
            </div>

            <div class="space-y-5">
                <div>
                    <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">Toggles</h3>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                        {#each settingsArray as [name, key]}
                            {@const on = !!settingsHash[name]}
                            <div class="flex items-center gap-3 p-2.5 rounded border {on ? 'bg-emerald-50 border-emerald-200' : 'bg-gray-50 border-gray-200'}">
                                <kbd class="inline-flex items-center justify-center w-7 h-7 rounded border border-gray-300 bg-white font-mono text-xs">{key}</kbd>
                                <div class="flex-1 font-medium text-gray-800">{name}</div>
                                <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[11px] font-semibold {on ? 'bg-emerald-200 text-emerald-900' : 'bg-gray-200 text-gray-600'}">
                                    <span class="w-1.5 h-1.5 rounded-full {on ? 'bg-emerald-600' : 'bg-gray-400'}"></span>
                                    {on ? 'on' : 'off'}
                                </span>
                            </div>
                        {/each}
                    </div>
                </div>

                <div>
                    <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">Modifier Key</h3>
                    <p class="text-xs text-gray-600 mb-2">Used together with letters for input-mode shortcuts (delete line, merge segment, etc). Only one modifier is active at a time.</p>
                    <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
                        {#each modifiers as m, i}
                            {@const active = currentModifier === m.id}
                            <button
                                type="button"
                                onclick={() => onSelectModifier(m.id)}
                                class="flex flex-col items-center gap-1 p-3 rounded border transition-colors {active ? 'bg-indigo-50 border-indigo-400 ring-2 ring-indigo-200' : 'bg-gray-50 border-gray-200 hover:border-indigo-200'}"
                            >
                                <div class="flex items-center gap-1.5">
                                    <kbd class="inline-flex items-center justify-center min-w-[28px] h-7 px-2 rounded border border-gray-300 bg-white font-mono text-xs">{m.label}</kbd>
                                    <span class="text-[10px] text-gray-500">({i + 1})</span>
                                </div>
                                <div class="text-xs font-semibold {active ? 'text-indigo-900' : 'text-gray-700'}">{m.name}</div>
                                {#if active}
                                    <span class="text-[10px] text-indigo-700 font-semibold">active</span>
                                {/if}
                            </button>
                        {/each}
                    </div>
                </div>
            </div>
        </div>
    {/snippet}
</BaseDialog>
