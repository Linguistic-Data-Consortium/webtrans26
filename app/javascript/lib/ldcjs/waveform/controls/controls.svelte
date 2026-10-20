<script>
    import { tick, createEventDispatcher, onMount, onDestroy } from 'svelte';
    import { event } from '../../../../guides/guide';
    import { btn, cbtn, dbtn, btn1 } from '../../work/buttons';
    import { ArrowUpFromLine, ArrowDownToLine, Check, X, House, Crosshair, Captions, Waypoints, MessageSquare, UserRound } from '@lucide/svelte';
    import * as Popover from "$lib/components/ui/popover";
    import * as Card from "$lib/components/ui/card";
    import * as RadioGroup from "$lib/components/ui/radio-group";
    import { Button } from "$lib/components/ui/button";
    import { Label } from "$lib/components/ui/label";
    import Keyboard from './keyboard.svelte';
    import { times, selection, round_to_3_places, round_to_6_places } from '../times';
    import {
        done,
        broken,
        delete_all
    } from '../modification1';
    import {
        CloseKitDialog,
        UploadTranscriptDialog,
        DownloadTranscriptDialog,
        DeleteAllDialog
    } from '../dialogs';
    import {
        set_playback_rate
    } from '../../audio/main';
    import { settings, mouse, key } from '../stores';
    import { fmap_helper, display_docid } from '../helpers';
    import { activeo } from '../shared.svelte';
    import { getp } from '../../getp';
    let {
        redact_task,
        muted,
        constraint_import_transcript,
        permissions,
        permission_to_download,
        constraint_audit,
        done_comment,
        dialog_close_kit_audit,
        broken_comment,
        show_asr,
        asr,
        mouseup,
        keydown,
        data_set_id,
        data_set_file_name,
        update_segments,
        update_segments2,
        update_segments2_with_blanks,
        add_save_asr,
        show_graph,
        kit_id,
        kit_source_uid,
        follow_active_segment = $bindable(),
        // Comments live in a panel under the transcript; this is its switch.
        // Only offered where the kit type asks for them.
        constraint_comments = false,
        speaker_is_subject = $bindable(false),
        comments_open = $bindable(false)
    } = $props();
    // The annotation-graph panel lives under the transcript (waveform.svelte);
    // this is only its trigger. Still being evaluated, so it's shown to one
    // account rather than to annotators — the endpoint has its own check.
    const graph_button_user_id = '1';
    // Loaded with ?graph=1, so the tree came out of the graph projection rather
    // than the annotation log. Worth saying out loud during a trial.
    // Which route this kit's tree came by: graph_memory (the default),
    // log, or graph (what a snapshot stored). Shown while the graph shape is
    // still being proven.
    const payload_source = window.ldc?.obj2?.payload_source;
    const header_data = document.getElementById('headerdata').dataset;

    let dialog_upload_transcript = $state();
    let dialoguploadtranscript = $state();
    export function create_transcript_retrieve2(){
        dialoguploadtranscript.create_transcript_retrieve2();
    }
    // Skip the dialog and apply one import choice directly ('readonly' | 'blanks' | 'save').
    export function auto_import(mode){
        dialoguploadtranscript.auto_import(mode);
    }
    // let wave_selection_offset = $state();
    // let wave_selection_end = $state();
    // const un4 = selection.subscribe( (x) => {
    //     wave_selection_offset = x.wave_selection_offset;
    //     // wave_selection_length = x.wave_selection_length;
    //     wave_selection_end = x.wave_selection_end;
    // } );
    // onDestroy( () => {
    //     un4();
    // } );
    let playback_rate = $state(1.0);
    // Filename display cycles through three forms on click:
    //   0 → short docid (basename of the audio, via display_docid)
    //   1 → full source (the kit's own source path, verbatim)
    //   2 → kit uid     (the kit_id prop)
    // Modes 0 and 1 are deliberately different strings for a JSON-wrapper kit:
    // activeo.docid is the audio the wrapper resolves to (its `wav`), while
    // kit_source_uid is the `.json` the kit was created from. Showing the
    // resolved audio as the "full" path read as an extension swap.
    let filename_display_mode = $state(0);
    const filename_display_labels = ['short docid', 'full source', 'kit uid'];
    let filename_copy_status = $state(''); // '', 'copied', 'failed'
    // Kits whose source is the audio itself have no separate wrapper path; fall
    // back to the docid so the mode still shows something.
    function filename_full_source() {
        return kit_source_uid || activeo.docid;
    }
    function filename_current_value() {
        if (filename_display_mode === 0) return display_docid(activeo.docid);
        if (filename_display_mode === 1) return filename_full_source();
        return kit_id;
    }
    async function copy_filename() {
        const text = filename_current_value();
        if (!text) return;
        try {
            await navigator.clipboard.writeText(String(text));
            filename_copy_status = 'copied';
        } catch (_) {
            filename_copy_status = 'failed';
        }
        setTimeout(() => { filename_copy_status = ''; }, 1500);
    }
    const playback_rates = [ 0.8, 1.0, 1.5, 2.0 ];
    $effect(() => {
        set_playback_rate(playback_rate);
    });
    let dialogclosekit = $state();
    let dialog_close_kit = $state();
    let dialog_download_transcript = $state();
    let keyboard;
    export function keyboard_focus(){
        keyboard.focus();
    }
    let dialog_close_kit_donef_popover_isopen = $state(false);
    function dialog_close_kit_donef(){
        // dialog_close_kit_donef_popover_isopen = false;
        // let c = null;
        // if(done_comment && done_comment.length) c = done_comment;
        // done(c);
        dialogclosekit.dialog_close_kit_donef();
    }
    function dialog_close_kit_donef_c(c){
        done_comment = c;
        dialog_close_kit_donef();
    }
    function dialog_close_kit_brokenf(){
        let c = null;
        if(broken_comment && broken_comment.length) c = broken_comment;
        broken(c);
    }
    function show(x){
        if(x == 'upload_transcript'){
            dialog_upload_transcript.showModal()
            // if(constraint_import_transcript_auto) data_set_file_name = docid;
            if(data_set_file_name) dialoguploadtranscript.create_transcript_retrieve();
            dialoguploadtranscript.upload_transcriptf();
            // if(ns.task_id == 77 || ns.task_id == 79){
            //     autoloading = true;
            //     create_transcript_autox = false;
            //     create_transcript_json = parse_sad_with_aws(create_transcript_text);
            //     create_transcript_add_save();
            // }
        }
        if(x == 'download_transcript') dialog_download_transcript.showModal();
        if(x == 'close_kit'){
            dialog_close_kit.showModal();
            event.dispatch(dialog_close_kit, 'drew_done');
        }
        if(x == 'delete_all') dialog_delete_all.showModal();
    }

    let dialog_delete_all = $state();
    function delete_all_wrapper(){
        // Close first. The dialog hiding and the progress panel appearing are
        // both state changes, so they paint together — and the annotator should
        // see the operation start, not watch the dialog sit there while it runs.
        //
        // delete_all takes no callback; the render is the $effect in
        // waveform.svelte, which folds once when the panel comes down.
        dialog_delete_all.close();
        delete_all();
    }

    key.subscribe((e) => {
        if(!e) return;
        const map = {
            'D': 'delete_all'
        }
        const x = fmap_helper(e, map);
        if(x) show(x, e);
    });
    
    const data = header_data;
  function unlock(){
    getp(`/kits/${data.kitid}/unlock_tree`).then( (x) => {
      console.log(x);
      window.location.reload();
    } );
  }

</script>

<CloseKitDialog
    bind:this={dialogclosekit}
    bind:dialogRef={dialog_close_kit}
    {dialog_close_kit_donef_popover_isopen}
    {dialog_close_kit_donef_c}
    {dialog_close_kit_brokenf}
/>

<UploadTranscriptDialog
    bind:this={dialoguploadtranscript}
    bind:dialogRef={dialog_upload_transcript}
    {data_set_id}
    {data_set_file_name}
    ldcPermissions={ldc.permissions}
    {update_segments2}
    {update_segments2_with_blanks}
    {add_save_asr}
/>

<DownloadTranscriptDialog
    bind:dialogRef={dialog_download_transcript}
    {kit_id}
/>

<DeleteAllDialog bind:dialogRef={dialog_delete_all} onConfirm={delete_all_wrapper} {btn} {dbtn} />

<div id="node-00-header" class="grid grid-cols-12">
    <div class="filename col-span-5" use:event.dispatch={'drew_filename'}>
        <div class="flex items-start gap-2 min-w-0">
            <button
                type="button"
                onclick={copy_filename}
                title={`copy ${filename_display_labels[filename_display_mode]}`}
                aria-label={`copy ${filename_display_labels[filename_display_mode]}`}
                class="shrink-0 text-[10px] text-gray-500 hover:text-gray-800 px-1.5 py-0.5 border border-gray-300 rounded"
            >{filename_copy_status === 'copied' ? '✓' : filename_copy_status === 'failed' ? '⚠' : 'copy'}</button>
            <!-- svelte-ignore a11y_click_events_have_key_events -->
            <!-- svelte-ignore a11y_no_static_element_interactions -->
            <div
                onclick={() => filename_display_mode = (filename_display_mode + 1) % 3}
                title={`showing ${filename_display_labels[filename_display_mode]} — click to cycle`}
                class="cursor-pointer select-none flex-1 min-w-0 {filename_display_mode === 1 ? 'break-all' : 'truncate'}"
            >{filename_display_mode === 0
                ? display_docid(activeo.docid)
                : filename_display_mode === 1
                    ? filename_full_source()
                    : kit_id}</div>
        </div>
        {#if redact_task}
            <div>REDACT</div>
        {/if}
    </div>
    <div class="col-span-4">
        <span>{activeo.wave_selection_offset} {activeo.wave_selection_end}</span>
        <span class="{muted ? 'text-black' : 'text-white'}">muted</span>
        <span class="pl-6">
            {#each playback_rates as x}
                <button
                    class="px-1 mx-1 rounded {x == playback_rate ? 'bg-red-200' : 'bg-gray-200'}"
                    onclick={ () => playback_rate = x }
                >
                    x{x}{x == '0.8' || x == '1.5' ? '' : '.0' }
                </button>
            {/each}
        </span>
    </div>
    <div class="col-span-3">
        <div class="grid grid-cols-12">
            {#if constraint_import_transcript || permissions.project_manager}
                <div class="col-span-2">
                    <button class={btn} onclick={ () => show('upload_transcript') }>
                        <ArrowUpFromLine size=20 />
                    </button>
                </div>
            {/if}
            {#if permission_to_download}
                <div class="col-span-2">
                    <button class={btn} onclick={ () => show('download_transcript') }>
                        <ArrowDownToLine size=20 />
                    </button>
                </div>
            {/if}
            {#if payload_source}
                <div class="col-span-2">
                    <span
                        class="text-xs px-1 rounded {payload_source === 'log' ? 'bg-gray-200' : 'bg-amber-200'}"
                        title="The tree was built via {payload_source}. ?payload=log on this page loads it from the annotation log instead."
                    >{payload_source}</span>
                </div>
            {/if}
            {#if header_data.userid == graph_button_user_id}
                <div class="col-span-2">
                    <button class={btn} onclick={show_graph} title="Show the annotation graph the kit loaded with, under the transcript">
                        <Waypoints size=20 />
                    </button>
                </div>
            {/if}
            {#if constraint_comments}
                <div class="col-span-2">
                    <!-- Show or hide the comments panel under the transcript.
                         Green (cbtn) while it's open. -->
                    <button
                        class={comments_open ? cbtn : btn}
                        onclick={ () => comments_open = !comments_open }
                        title="{comments_open ? 'Hide' : 'Show'} comments"
                        aria-pressed={comments_open}
                    >
                        <MessageSquare size=20 />
                    </button>
                </div>
            {/if}
            <div class="col-span-2">
                <!-- When on, the speaker command skips the speaker menu and sets
                     the segment's speaker to "subject". On a recording with one
                     person of interest, picking the same name out of a menu every
                     time is the whole cost of labelling a speaker. -->
                <button
                    class={speaker_is_subject ? cbtn : btn}
                    onclick={ () => speaker_is_subject = !speaker_is_subject }
                    title={speaker_is_subject
                        ? 'Speaker command sets "subject" — click to choose from the menu instead'
                        : 'Speaker command opens the menu — click to always set "subject"'}
                    aria-pressed={speaker_is_subject}
                >
                    <UserRound size=20 />
                </button>
            </div>
            <div class="col-span-2">
                <!-- Toggle auto-scroll/zoom to follow the active transcript line.
                     Green (cbtn) when on, gray (btn) when off. -->
                <button
                    class={follow_active_segment ? cbtn : btn}
                    onclick={ () => follow_active_segment = !follow_active_segment }
                    title="{follow_active_segment ? 'Disable' : 'Enable'} auto-scroll to the active segment"
                    aria-pressed={follow_active_segment}
                >
                    <Crosshair size=20 />
                </button>
            </div>
            <div class="col-span-2 float-left submit-button" use:event.dispatch={'drew_submit'}>
                {#if constraint_audit}
                    <Popover.Root  bind:open={dialog_close_kit_donef_popover_isopen} >
                        <Popover.Trigger>
                            <!-- svelte-ignore a11y_consider_explicit_label -->
                            <button class={btn}>
                                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                                </svg>
                            </button>
                        </Popover.Trigger>
                        <Popover.Content>
                            <Card.Root>
                              <Card.Header>
                                <Card.Title>Close Transcript</Card.Title>
                                <Card.Description>Move to Next File</Card.Description>
                              </Card.Header>
                              <Card.Content>
                                    <div><Button variant="outline" class="w-full mb-2" onclick={() => dialog_close_kit_donef_c("yes")}>Done comment Yes</Button></div>
                                    <div><Button variant="outline" class="w-full mb-2" onclick={() => dialog_close_kit_donef_c("no")}>Done comment No</Button></div>
                                    <div><Button variant="outline" class="w-full mb-2" onclick={() => dialog_close_kit_donef_c("maybe")}>Done comment Maybe</Button></div>
                                    <div><button class="{cbtn} w-full mb-2 submit-done-button" onclick={dialog_close_kit_donef} use:event.dispatch={'drew_done'}>Done</button></div>
                                    <textarea
                                        class="mb-2 focus:ring-indigo-500 focus:border-indigo-500 flex-1 block w-full rounded-md border-gray-300"
                                        bind:value={done_comment}
                                        placeholder="comment (optional)"
                                    ></textarea>
                                    <div
                                        class="after:border-border relative text-center text-sm after:absolute after:inset-0 after:top-1/2 after:z-0 after:flex after:items-center after:border-t"
                                    >
                                        <span class="bg-card text-muted-foreground relative z-10 px-2">
                                            Was there a problem with this file?
                                        </span>
                                    </div>
                                    <hr class="mb-2">
                                    <RadioGroup.Root bind:value={dialog_close_kit_audit} class="mb-2" >
                                        <div class="flex items-center space-x-2">
                                            <RadioGroup.Item value="skip" id="option-skip"
                                                class="focus:ring-indigo-500 focus:border-indigo-500 h-4 w-4 border-gray-300"
                                            />
                                            <Label for="option-skip">Skip</Label>
                                        </div>
                                        <div class="flex items-center space-x-2">
                                            <RadioGroup.Item value="broken" id="option-broken"
                                                class="focus:ring-indigo-500 focus:border-indigo-500 h-4 w-4 border-gray-300"
                                            />
                                            <Label for="option-broken">Broken</Label>
                                        </div>
                                    </RadioGroup.Root>
                                    {#if dialog_close_kit_audit == 'broken' }
                                        <textarea
                                        class="mb-2 focus:ring-indigo-500 focus:border-indigo-500 flex-1 block w-full rounded-md border-gray-300"
                                        bind:value={broken_comment}
                                        placeholder="comment (optional)"
                                        ></textarea>
                                    {/if}
                                    {#if dialog_close_kit_audit == 'skip'}
                                        <div><button class="{dbtn} w-full" data-close-dialog onclick={skip}>Confirm Skip</button></div>
                                    {/if}
                                    {#if dialog_close_kit_audit == 'broken'}
                                        <div><button class="{dbtn} w-full" data-close-dialog onclick={dialog_close_kit_brokenf}>Confirm Broken</button></div>
                                    {/if}
                              </Card.Content>
                              <Card.Footer>
                              </Card.Footer>
                            </Card.Root>
                        </Popover.Content>
                    </Popover.Root>
                {:else}
                    <!-- svelte-ignore a11y_consider_explicit_label -->
                    <button class={btn} onclick={ () => show('close_kit') }>
                        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                        </svg>
                    </button>
                {/if}
            </div>
            {#if show_asr}
                <!-- svelte-ignore a11y_click_events_have_key_events -->
                <!-- svelte-ignore a11y_no_static_element_interactions -->
                <div class="col-span-1 float-left cursor-pointer" onclick={asr} title="Speech recognition">
                    <Captions />
                </div>
            {/if}
            <Keyboard bind:this={keyboard} />
            <a href="/"><House /></a>
        </div>
        {#if data.locked}
            <button class="{btn}" onclick={unlock}>unlock</button>
        {/if}
    </div>
</div>
