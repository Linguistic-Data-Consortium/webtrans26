<script>
    import BaseDialog from './BaseDialog.svelte';

    let {
        dialogRef = $bindable(),
        onConfirm = null,
        btn = "",
        dbtn = ""
    } = $props();
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-md" title="Delete Section">
    {#snippet children({ dialog })}
        <div class="p-6">
            <div class="flex items-start">
                <svg class="h-6 w-6 text-orange-500 mr-3 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
                <div>
                    <p class="text-gray-700">
                        Are you sure you want to delete the selected section?
                    </p>
                    <p class="mt-2 text-sm text-gray-500">
                        This action cannot be undone.
                    </p>
                </div>
            </div>
        </div>
        <div class="bg-gray-50 px-6 py-4 flex justify-end gap-3 rounded-b-xl border-t border-gray-200">
            <button type="button" onclick={() => dialog.close()} class="{btn}">Cancel</button>
            <button type="button" onclick={onConfirm} class="{dbtn}">Delete Section</button>
        </div>
    {/snippet}
</BaseDialog>
