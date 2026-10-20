<script>
    import BaseDialog from './ldcjs/waveform/dialogs/BaseDialog.svelte';

    let {
        dialogRef = $bindable(),
        extraBindings = []
    } = $props();

    const builtin = [
        { key: 'f',   desc: 'Show hint letters on all actionable elements; type the letter to activate' },
        { key: 'h',   desc: 'Show this cheat sheet' },
        { key: 'd',   desc: 'Open documentation' },
        { key: 's',   desc: 'Sign out (asks for confirmation; y to confirm, n to cancel)' },
        { key: 'esc', desc: 'Cancel hint overlay / close this dialog' }
    ];
    // Page-specific bindings render first so they get top billing —
    // the per-page interesting stuff (guide, admin jump, etc) is what
    // first-time users want to discover.
    let all_bindings = $derived([...extraBindings, ...builtin]);

    function focus(x) { x.focus(); }
    function onKeydown(e) {
        dialogRef.close();
    }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-3xl" title="Keyboard Cheat Sheet" {onKeydown} showClose={false}>
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div use:focus tabindex="0" onkeydown={onKeydown} class="p-5 outline-none text-sm">
            <div class="bg-amber-50 border border-amber-200 rounded p-2 mb-4 flex items-center gap-3 text-xs">
                <span class="text-amber-900">Press <kbd class="px-1.5 py-0.5 bg-white rounded font-mono shadow-sm">h</kbd> any time to reopen.</span>
                <span class="ml-auto text-amber-700">Press any other key to dismiss.</span>
            </div>

            <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">Keys</h3>
            <div class="space-y-1">
                {#each all_bindings as b}
                    <div class="flex items-center p-1.5 bg-gray-50 rounded">
                        <kbd class="px-1.5 py-0.5 bg-white border border-gray-300 rounded font-mono text-xs mr-2 min-w-[60px] text-center">{b.key}</kbd>
                        <span class="text-gray-700 text-xs">{b.desc}</span>
                    </div>
                {/each}
            </div>
        </div>
    {/snippet}
</BaseDialog>
