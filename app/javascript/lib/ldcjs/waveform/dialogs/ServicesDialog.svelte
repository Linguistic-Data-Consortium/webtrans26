<script>
    import BaseDialog from './BaseDialog.svelte';
    import { services_configured } from '../../service_config';
    import { local_audio_active } from '../../local_audio';
    import { local_asr_available } from '../../local_asr';
    import { energy_available } from '../energy_run';

    let {
        dialogRef = $bindable(),
        onKeydown = null
    } = $props();

    function focus(x) { x.focus(); }

    // Two independent questions, because the answers stopped agreeing once
    // recognition could run in the page:
    //
    //   hosted  — may we send this audio away, and is there anywhere to send
    //             it? No for a local_audio kit, no for an instance with no
    //             HLT_ENDPOINT / PROMISE_BUCKET.
    //   local   — can this browser run a model itself?
    //   energy  — can it decode audio, to find segments from the sound level?
    //
    // Any one alone is a usable menu. Only when all are false is there
    // nothing to offer, and that is the one case that shows a notice.
    const hosted = () => services_configured() && !local_audio_active();
    const local  = () => local_asr_available();
    const energy = () => energy_available();
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-2xl" title="Available Services" {onKeydown} showClose={false}>
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div use:focus tabindex="0" onkeydown={onKeydown} class="p-6 outline-none">
            {#if !hosted() && !local() && !energy()}
            {#if local_audio_active()}
                <!-- The audio is a file on the annotator's computer, and every
                     service here works by sending it away. -->
                <div class="bg-amber-50 border border-amber-200 rounded-lg p-4">
                    <p class="text-sm text-amber-900">
                        This kit's audio is a file on your computer, and it stays there,
                        so no speech services are available for it.
                    </p>
                    <p class="mt-3 text-sm text-amber-900">
                        Press <kbd class="px-2 py-1 bg-white rounded text-amber-900 font-mono text-xs shadow-sm">h</kbd> to return to the main menu
                    </p>
                </div>
            {:else}
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
            {/if}
            {:else}
            <div class="bg-amber-50 border border-amber-200 rounded-lg p-3 mb-6">
                <p class="text-sm text-amber-900">
                    Press <kbd class="px-2 py-1 bg-white rounded text-amber-900 font-mono text-xs shadow-sm">h</kbd> to return to the main menu
                </p>
            </div>

            {#if !hosted()}
                <!-- The menu is not empty, but only what runs in the browser is
                     in it, and an annotator who expected SAD and ASR deserves
                     to know which of the two reasons applies. -->
                <div class="bg-amber-50 border border-amber-200 rounded-lg p-3 mb-6 text-sm text-amber-900">
                    {#if local_audio_active()}
                        This kit's audio is a file on your computer and it stays
                        there, so the services that would send it away are not
                        available. What runs in this browser is.
                    {:else}
                        No hosted speech services are configured on this server,
                        so only what runs in this browser is available.
                    {/if}
                </div>
            {/if}

            <div class="space-y-3">
                {#if hosted()}
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
                {/if}

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
