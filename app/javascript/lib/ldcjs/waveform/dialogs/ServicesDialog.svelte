<script>
    import BaseDialog from './BaseDialog.svelte';
    import { services_configured } from '../../service_config';

    let {
        dialogRef = $bindable(),
        onKeydown = null
    } = $props();

    function focus(x) { x.focus(); }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-2xl" title="Available Services" {onKeydown} showClose={false}>
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div use:focus tabindex="0" onkeydown={onKeydown} class="p-6 outline-none">
            {#if !services_configured()}
                <!-- Nowhere to send the work, so don't offer a numbered menu
                     whose every option would fail. This is a normal state for
                     an install that only needs manual transcription. -->
                <div class="bg-amber-50 border border-amber-200 rounded-lg p-4">
                    <p class="text-sm text-amber-900">
                        No speech services are configured on this server, so none are
                        available. An administrator can enable them by setting
                        <tt class="font-mono">HLT_ENDPOINT</tt> and
                        <tt class="font-mono">PROMISE_BUCKET</tt>.
                    </p>
                    <p class="mt-3 text-sm text-amber-900">
                        Press <kbd class="px-2 py-1 bg-white rounded text-amber-900 font-mono text-xs shadow-sm">h</kbd> to return to the main menu
                    </p>
                </div>
            {:else}
            <div class="bg-amber-50 border border-amber-200 rounded-lg p-3 mb-6">
                <p class="text-sm text-amber-900">
                    Press <kbd class="px-2 py-1 bg-white rounded text-amber-900 font-mono text-xs shadow-sm">h</kbd> to return to the main menu
                </p>
            </div>

            <div class="space-y-3">
                <div class="flex items-center p-4 bg-gradient-to-r from-blue-50 to-indigo-50 rounded-lg border border-blue-200 hover:border-indigo-300 transition-colors">
                    <div class="flex-shrink-0 w-10 h-10 bg-blue-600 text-white rounded-lg flex items-center justify-center font-bold text-lg mr-4 shadow-sm">
                        1
                    </div>
                    <div>
                        <div class="font-semibold text-gray-900 text-lg">SAD</div>
                        <div class="text-sm text-gray-600">Speech Activity Detection</div>
                    </div>
                </div>

                <div class="flex items-center p-4 bg-gradient-to-r from-purple-50 to-pink-50 rounded-lg border border-purple-200 hover:border-pink-300 transition-colors">
                    <div class="flex-shrink-0 w-10 h-10 bg-purple-600 text-white rounded-lg flex items-center justify-center font-bold text-lg mr-4 shadow-sm">
                        2
                    </div>
                    <div>
                        <div class="font-semibold text-gray-900 text-lg">ASR</div>
                        <div class="text-sm text-gray-600">Automatic Speech Recognition</div>
                    </div>
                </div>

                <div class="flex items-center p-4 bg-gradient-to-r from-green-50 to-emerald-50 rounded-lg border border-green-200 hover:border-emerald-300 transition-colors">
                    <div class="flex-shrink-0 w-10 h-10 bg-green-600 text-white rounded-lg flex items-center justify-center font-bold text-lg mr-4 shadow-sm">
                        3
                    </div>
                    <div>
                        <div class="font-semibold text-gray-900 text-lg">ASR (Korean)</div>
                        <div class="text-sm text-gray-600">Korean Language Speech Recognition</div>
                    </div>
                </div>

                <div class="flex items-center p-4 bg-gradient-to-r from-orange-50 to-amber-50 rounded-lg border border-orange-200 hover:border-amber-300 transition-colors">
                    <div class="flex-shrink-0 w-10 h-10 bg-orange-600 text-white rounded-lg flex items-center justify-center font-bold text-lg mr-4 shadow-sm">
                        4
                    </div>
                    <div>
                        <div class="font-semibold text-gray-900 text-lg">ASR (Rev.ai)</div>
                        <div class="text-sm text-gray-600">Rev.ai Speech Recognition Service</div>
                    </div>
                </div>
            </div>

            <div class="mt-6 pt-4 border-t border-gray-200">
                <p class="text-xs text-gray-500 text-center">
                    Press the corresponding number to select a service
                </p>
            </div>
            {/if}
        </div>
    {/snippet}
</BaseDialog>
