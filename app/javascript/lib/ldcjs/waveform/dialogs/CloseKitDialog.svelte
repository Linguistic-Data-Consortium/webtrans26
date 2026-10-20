<script>
    import BaseDialog from './BaseDialog.svelte';
    import { btn, cbtn, dbtn, btn1 } from '../../work/buttons';
    import { event } from '../../../../guides/guide';
    import {
        done,
        skip
    } from '../modification1';

    let {
        dialogRef = $bindable(),
        dialog_close_kit_donef_popover_isopen = $bindable(),
        dialog_close_kit_brokenf
    } = $props();
    let dialog_close_kit_audit = $state();
    let done_comment = $state();
    let broken_comment = $state();
    // let dialog_close_kit_donef_popover_isopen = $state(false);
    export function dialog_close_kit_donef(){
        dialog_close_kit_donef_popover_isopen = false;
        let c = null;
        if(done_comment && done_comment.length) c = done_comment;
        done(c);
    }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-3xl" title="Close Transcript, Move to Next File">
    {#snippet children({ dialog })}
        <div class="overflow-auto p-6">
            <div class="space-y-4">
                <div>
                    <button class="{cbtn} w-full py-3 text-lg font-medium" onclick={dialog_close_kit_donef} use:event.dispatch={'drew_done'}>✓ Done</button>
                </div>

                <textarea
                    class="focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 block w-full rounded-lg border-gray-300 shadow-sm px-4 py-3"
                    bind:value={done_comment}
                    placeholder="Add optional comment..."
                    rows="3"
                ></textarea>

                <div class="border-t border-gray-200 pt-4">
                    <h4 class="font-medium text-gray-900 mb-3">Was there a problem with this file?</h4>
                    <div class="space-y-3 pl-2">
                        <label class="flex items-center space-x-3 cursor-pointer hover:bg-gray-50 p-2 rounded-lg transition">
                            <input
                                class="focus:ring-2 focus:ring-indigo-500 h-5 w-5 text-indigo-600 border-gray-300 rounded"
                                type="radio"
                                bind:group={dialog_close_kit_audit}
                                value="skip"
                            />
                            <span class="text-gray-700 font-medium">Skip this file</span>
                        </label>

                        <label class="flex items-center space-x-3 cursor-pointer hover:bg-gray-50 p-2 rounded-lg transition">
                            <input
                                class="focus:ring-2 focus:ring-indigo-500 h-5 w-5 text-indigo-600 border-gray-300 rounded"
                                type="radio"
                                bind:group={dialog_close_kit_audit}
                                value="broken"
                            />
                            <span class="text-gray-700 font-medium">Mark as broken</span>
                        </label>
                    </div>
                </div>

                {#if dialog_close_kit_audit === 'broken'}
                    <textarea
                        class="focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 block w-full rounded-lg border-gray-300 shadow-sm px-4 py-3"
                        bind:value={broken_comment}
                        placeholder="Describe the issue..."
                        rows="3"
                    ></textarea>
                {/if}

                {#if dialog_close_kit_audit === 'skip'}
                    <button class="{dbtn} w-full py-3 text-lg font-medium" data-close-dialog onclick={skip}>Confirm Skip</button>
                {/if}
                {#if dialog_close_kit_audit === 'broken'}
                    <button class="{dbtn} w-full py-3 text-lg font-medium" data-close-dialog onclick={dialog_close_kit_brokenf}>Confirm Broken</button>
                {/if}
            </div>
        </div>
    {/snippet}
</BaseDialog>
