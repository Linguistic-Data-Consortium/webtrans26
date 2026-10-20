<script>
    import BaseDialog from './BaseDialog.svelte';
    import ServiceResponse from '../service_response.svelte';

    let {
        dialogRef = $bindable(),
        addWhich,
        addSadP2,
        addSadP3
    } = $props();

    function focus(x) { x.focus(); }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-3xl" title="Speech Activity Detection">
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div use:focus tabindex="0" onkeydown={() => null} class="p-6 min-h-96 overflow-auto">
            <div class="w-full">
                {#if addWhich === 'sad'}
                    <div class="bg-gradient-to-br from-blue-50 to-indigo-50 rounded-lg p-6">
                        <ServiceResponse
                            p1={null}
                            p2={addSadP2}
                            p3={addSadP3}
                            m1={"prep sad..."}
                            m2={"running sad..."}
                            m3={"creating segments..."}
                        />
                    </div>
                {/if}
            </div>
        </div>
    {/snippet}
</BaseDialog>
