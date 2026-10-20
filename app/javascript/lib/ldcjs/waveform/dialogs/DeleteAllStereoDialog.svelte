<script>
    import BaseDialog from './BaseDialog.svelte';

    let {
        dialogRef = $bindable(),
        onConfirm = null,
        btn = "",
        dbtn = ""
    } = $props();
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-md" title="Delete Stereo Lines">
    {#snippet children({ dialog })}
        <div class="p-6">
            <div class="flex items-start">
                <svg class="h-6 w-6 text-red-600 mr-3 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <div>
                    <p class="text-gray-700">
                        There appear to be <strong class="font-semibold">stereo docids</strong> in this transcript.
                    </p>
                    <p class="mt-2 text-sm text-gray-600">
                        Do you want to delete all lines with stereo docids? This action cannot be undone.
                    </p>
                </div>
            </div>
        </div>
        <div class="bg-gray-50 px-6 py-4 flex justify-end gap-3 rounded-b-xl border-t border-gray-200">
            <button type="button" onclick={() => dialog.close()} class="{btn}">Cancel</button>
            <button type="button" onclick={onConfirm} class="{dbtn}">Delete All Stereo</button>
        </div>
    {/snippet}
</BaseDialog>
