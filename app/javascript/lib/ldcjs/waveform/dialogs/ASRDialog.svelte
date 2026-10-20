<script>
    import BaseDialog from './BaseDialog.svelte';
    import ServiceResponse from '../service_response.svelte';

    let {
        dialogRef = $bindable(),
        addWhich
    } = $props();

    function focus(x) { x.focus(); }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-3xl" title="Automatic Speech Recognition">
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div use:focus tabindex="0" onkeydown={() => null} class="p-6 min-h-96 overflow-auto">
            {#if addWhich === 'sad' || addWhich == 'asr'}
                <div class="bg-gradient-to-br from-purple-50 to-pink-50 rounded-lg p-6">
                    <ServiceResponse
                    />
                </div>
            {/if}
        </div>
    {/snippet}
</BaseDialog>
