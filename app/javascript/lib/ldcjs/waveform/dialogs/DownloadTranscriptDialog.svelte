<script>
    import { tick, createEventDispatcher, onMount, onDestroy } from 'svelte';
    import { btn, cbtn, dbtn, btn1 } from '../../work/buttons';
    import { create_download_url } from '../../download_helper';
    import { create_transcript } from '../download_transcript_helper';
    import { transcript, graph } from '../transcript.svelte';
    import BaseDialog from './BaseDialog.svelte';

    let {
        dialogRef = $bindable(),
        kit_id
    } = $props();

    const segs = $derived(transcript.segments);

    let download_transcript_text = $state();
    let download_transcript_json = $state();
    let download_transcript_include_headers = $state(false);
    let download_transcript_filename = $state();
    let download_transcript_link = $state();
    let download_transcript_url = $state();
    let download_transcript_include_speaker = $state(false);
    let download_transcript_include_section = $state(false);
    // Set when the rows disagree with the annotation graph they were folded
    // from. No file is offered while it stands — the transcript is wrong, and
    // a downloaded copy of it would outlive the bug.
    let download_transcript_error = $state(null);
    function download_transcript_create(){
        let kit = kit_id;
        try{
            download_transcript_text = create_transcript(kit, download_transcript_include_speaker, download_transcript_include_section, download_transcript_include_headers, segs, graph);
        }
        catch(e){
            download_transcript_error = e.message;
            download_transcript_text = null;
            download_transcript_url = null;
            return;
        }
        download_transcript_error = null;
        download_transcript_url = create_download_url(download_transcript_text);
        tick().then( () => download_transcript_link.href = download_transcript_url );
    }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-4xl" title="Download Transcript">
    {#snippet children({ dialog })}
        <div class="overflow-auto p-6">
            <div class="space-y-6">
                <div>
                    <!-- svelte-ignore a11y_label_has_associated_control -->
                    <label class="block text-sm font-medium text-gray-700 mb-2">
                        Filename <span class="text-gray-500 text-xs">(.tsv will be appended)</span>
                    </label>
                    <input
                        class="focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 block w-full rounded-lg border-gray-300 shadow-sm px-4 py-2"
                        type="text"
                        bind:value={download_transcript_filename}
                        placeholder="transcript"
                    />
                </div>

                <div class="border-t border-gray-200 pt-4">
                    <!-- svelte-ignore a11y_label_has_associated_control -->
                    <label class="block text-sm font-medium text-gray-700 mb-3">Export Options</label>
                    <div class="space-y-3">
                        <label class="flex items-center space-x-3 cursor-pointer hover:bg-gray-50 p-2 rounded-lg transition">
                            <input
                                class="focus:ring-2 focus:ring-indigo-500 h-5 w-5 text-indigo-600 border-gray-300 rounded"
                                type="checkbox"
                                bind:checked={download_transcript_include_headers}
                            />
                            <div class="flex-1">
                                <span class="text-gray-900 font-medium">Include Headers</span>
                                <p class="text-sm text-gray-500">Add column headers to the file</p>
                            </div>
                        </label>

                        <label class="flex items-center space-x-3 cursor-pointer hover:bg-gray-50 p-2 rounded-lg transition">
                            <input
                                class="focus:ring-2 focus:ring-indigo-500 h-5 w-5 text-indigo-600 border-gray-300 rounded"
                                type="checkbox"
                                bind:checked={download_transcript_include_speaker}
                            />
                            <div class="flex-1">
                                <span class="text-gray-900 font-medium">Include Speaker</span>
                                <p class="text-sm text-gray-500">Add speaker information column</p>
                            </div>
                        </label>

                        <label class="flex items-center space-x-3 cursor-pointer hover:bg-gray-50 p-2 rounded-lg transition">
                            <input
                                class="focus:ring-2 focus:ring-indigo-500 h-5 w-5 text-indigo-600 border-gray-300 rounded"
                                type="checkbox"
                                bind:checked={download_transcript_include_section}
                            />
                            <div class="flex-1">
                                <span class="text-gray-900 font-medium">Include Section</span>
                                <p class="text-sm text-gray-500">Add section information column</p>
                            </div>
                        </label>
                    </div>
                </div>

                <div class="flex items-center gap-3 pt-2">
                    <button class="{btn} py-2 px-6" onclick={download_transcript_create}>Create Preview</button>
                    {#if download_transcript_url}
                        <!-- svelte-ignore a11y_missing_attribute -->
                        <a class="text-blue-600 hover:text-blue-800 font-medium underline" bind:this={download_transcript_link} download={download_transcript_filename}>
                            ⬇ Download File
                        </a>
                    {/if}
                </div>

                {#if download_transcript_error}
                    <div class="border border-red-300 bg-red-50 rounded-lg p-4">
                        <h4 class="text-sm font-medium text-red-800 mb-1">No file written</h4>
                        <p class="text-sm text-red-700">{download_transcript_error}</p>
                        <p class="text-xs text-red-600 mt-2">
                            The rows on screen don't match the annotation graph they were folded from,
                            so this transcript can't be trusted. Reload the kit and try again — the
                            console has the full comparison.
                        </p>
                    </div>
                {/if}

                {#if download_transcript_json || download_transcript_text}
                    <div class="border-t border-gray-200 pt-4">
                        <h4 class="text-sm font-medium text-gray-700 mb-2">Preview</h4>
                        <div class="bg-gray-50 rounded-lg p-4 max-h-64 overflow-auto">
                            {#if download_transcript_json}
                                <pre class="text-xs text-gray-800 font-mono">{#each download_transcript_json as x}{JSON.stringify(x) + "\n"}{/each}</pre>
                            {:else if download_transcript_text}
                                <pre class="text-xs text-gray-800 font-mono">{download_transcript_text}</pre>
                            {/if}
                        </div>
                    </div>
                {/if}
            </div>
        </div>
    {/snippet}
</BaseDialog>
