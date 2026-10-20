<script>
    import BaseDialog from './BaseDialog.svelte';

    let {
        dialogRef = $bindable()
    } = $props();
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-4xl">
    {#snippet children({ dialog })}
        <div class="shadow-xl bg-white border-2 rounded fixed right-80 top-48 opacity-100 z-10">
            <div class="grid grid-cols-2 gap-4">dialog_spectrogram
                <!-- placeholder for future spectrogram implementation -->
            </div>
        </div>
    {/snippet}
</BaseDialog>
