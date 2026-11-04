<script>
    import BaseDialog from './BaseDialog.svelte';
    import { local_asr_available } from '../../local_asr';
    import { energy_available } from '../energy_run';

    let {
        dialogRef = $bindable(),
        onKeydown = null
    } = $props();

    function focus(x) { x.focus(); }

    // Everything this menu offers runs in the annotator's own browser. The
    // hosted services — SAD and the three remote ASR engines, numbered 1 to 4
    // — are not offered here: they send the audio to a service this app does
    // not ship and cannot assume, so a public release has nothing to point
    // them at. The numbering keeps the gap rather than closing it, so these
    // two dialogs stay mergeable with the app they are copied from.
    //
    //   local   — can this browser run a model itself?
    //   energy  — can it decode audio, to find segments from the sound level?
    //
    // Either alone is a usable menu. Only when both are false is there nothing
    // to offer, and that is the one case that shows a notice.
    const local  = () => local_asr_available();
    const energy = () => energy_available();
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-2xl" title="Available Services" {onKeydown} showClose={false}>
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div use:focus tabindex="0" onkeydown={onKeydown} class="p-6 outline-none">
            {#if !local() && !energy()}
                <!-- Everything here runs in the browser, so when the browser can
                     do neither there is nothing to offer. Not an error and not a
                     misconfiguration: an older browser, or one without the
                     WebAssembly support recognition needs. -->
                <div class="bg-amber-50 border border-amber-200 rounded-lg p-4">
                    <p class="text-sm text-amber-900">
                        Nothing this menu offers can run in this browser. Speech
                        recognition and sound-level segmentation both run here rather
                        than on the server, and this browser supports neither.
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

                {#if local()}
                <div class="flex items-center p-4 bg-gradient-to-r from-teal-50 to-cyan-50 rounded-lg border border-teal-200 hover:border-cyan-300 transition-colors">
                    <div class="flex-shrink-0 w-10 h-10 bg-teal-600 text-white rounded-lg flex items-center justify-center font-bold text-lg mr-4 shadow-sm">
                        5
                    </div>
                    <div>
                        <div class="font-semibold text-gray-900 text-lg">ASR (in this browser)</div>
                        <div class="text-sm text-gray-600">
                            Runs on your computer — the audio is not sent anywhere.
                            Slower and less accurate, and the first run downloads
                            the model.
                        </div>
                    </div>
                </div>
                {/if}

                {#if energy()}
                <div class="flex items-center p-4 bg-gradient-to-r from-slate-50 to-gray-50 rounded-lg border border-slate-200 hover:border-gray-300 transition-colors">
                    <div class="flex-shrink-0 w-10 h-10 bg-slate-600 text-white rounded-lg flex items-center justify-center font-bold text-lg mr-4 shadow-sm">
                        6
                    </div>
                    <div>
                        <div class="font-semibold text-gray-900 text-lg">Segments from sound level</div>
                        <div class="text-sm text-gray-600">
                            Empty segments wherever the sound rises above the
                            background, in the gaps between existing ones. Runs
                            on your computer; nothing to download.
                        </div>
                    </div>
                </div>
                {/if}

                {#if local()}
                <div class="flex items-center p-4 bg-gradient-to-r from-teal-50 to-emerald-50 rounded-lg border border-teal-200 hover:border-emerald-300 transition-colors">
                    <div class="flex-shrink-0 w-10 h-10 bg-teal-700 text-white rounded-lg flex items-center justify-center font-bold text-lg mr-4 shadow-sm">
                        7
                    </div>
                    <div>
                        <div class="font-semibold text-gray-900 text-lg">ASR into empty segments (in this browser)</div>
                        <div class="text-sm text-gray-600">
                            Fills each segment that has no text yet, one at a
                            time; nothing is added or moved. To see suggestions
                            as you go instead, turn on ASR suggestions in the
                            toolbar.
                        </div>
                    </div>
                </div>
                {/if}
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
