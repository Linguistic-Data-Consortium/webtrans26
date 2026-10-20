<script>
    import BaseDialog from './BaseDialog.svelte';

    let {
        dialogRef = $bindable(),
        commandLine = $bindable(),
        onEnter = null,
        btn1 = ""
    } = $props();

    function handleKeyup(e) {
        if (e.key === 'Enter' || e.keyCode === 13) {
            onEnter?.();
        }
    }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-2xl" title="Enter Command">
    {#snippet children({ dialog })}
        <div class="p-6">
            <div class="mb-4">
                <!-- svelte-ignore a11y_autofocus -->
                <input
                    id="input-command"
                    class="focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 block w-full rounded-lg border-gray-300 shadow-sm px-4 py-3 text-lg"
                    type="text"
                    bind:value={commandLine}
                    aria-describedby="input-command-validation"
                    onkeyup={handleKeyup}
                    placeholder="Type command..."
                    autofocus
                />
            </div>
            <div class="flex justify-end gap-3">
                <button class="{btn1}" onclick={() => dialog.close()}>Cancel</button>
            </div>
        </div>
    {/snippet}
</BaseDialog>
