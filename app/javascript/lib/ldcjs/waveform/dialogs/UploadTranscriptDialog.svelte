<script>
    import { onDestroy } from 'svelte';
    import BaseDialog from './BaseDialog.svelte';
    import Spinner from '../../work/spinner.svelte';
    import parse_tsv from '../parse_tsv2';
    import parse_tsv0 from '../parse_tsv';
    import parse_tdf from '../parse_tdf';
    import parse_sad_with_aws from '../parse_sad_with_aws';
    import { btn, cbtn, dbtn, btn1 } from '../../work/buttons';

    let {
        dialogRef = $bindable(),
        data_set_id,
        data_set_file_name,
        ldcPermissions,
        update_segments2,
        update_segments2_with_blanks,
        add_save_asr
    } = $props();
    let create_transcript_auto = $state(false);
    let create_transcript_files = $state();
    let create_transcript_text = $state();
    let create_transcript_json = $state();
    let create_transcript_tsv = $state(false);
    let create_transcript_tdf = $state(false);
    let create_transcript_sad_with_aws = $state(false);
    let create_transcript_jsonn = $state();
    let autoloading = $state(false);
    export function create_transcript_retrieve(){
        console.log(data_set_id);
        console.log(data_set_file_name);
        if(data_set_id && data_set_file_name){
            // data_set_id = 3;
            let data_set_p = getp(`/data_sets/${data_set_id}?file_name=${data_set_file_name}`);
            data_set_p.then( (x) => {
                console.log(x);
                create_transcript_text = x.file;
                create_transcript_json = parse_tdf(create_transcript_text);
                create_transcript_add();
            } );
        }
    }
    export function upload_transcriptf(){
        if(create_transcript_auto) create_transcript_text = create_transcript_auto;
    }
    let intt;
    onDestroy( () => intt ? clearInterval(intt) : null);
    // let dialog_upload_transcript;
    export function create_transcript_retrieve2(){
        const o = ldc.maino;
        let r = Math.random();
        console.log('r ', r);
        // Use the bound <dialog> element directly. BaseDialog renders the dialog
        // without an id, so the old getElementById('dialog_upload_transcript')
        // lookup was always null and this method spun forever in the retry below.
        let d = dialogRef;
        create_transcript_auto = true;
        if(d){
            if(o && o.transcript){
                o.transcript.then( (x) => {
                    console.log('modal')
                    console.log(x);
                    // auto = x.found_transcript;
                    if(x.use_transcript == 'tsv'){
                        create_transcript_text = x.found_transcript;
                        const j = parse_tsv0(create_transcript_text);
                        intt = setInterval( () => set_create_transcript_json(j, r), 1000);
                    }
                    console.log(create_transcript_json)
                    d.showModal()
                    // if(x.use_transcript == 'tdf') tdf = true;
                    // if(x.use_transcript == 'sad_with_aws') sad_with_aws = true;
                    if(document.querySelectorAll('.segment').length > 0) auto = false;
                } );
            }
            else{
                console.log('no transcript ', r)
            }
        }
        else{
            console.log('waiting');
            setTimeout( () => create_transcript_retrieve2(), 1000);
        }
    }
    function set_create_transcript_json(x, r){
        console.log('setting4 ', r);
        // rando = Math.random();
        create_transcript_json = x;
    }
    function create_transcript_upload(){
        const r = new FileReader();
        let o = null;
        r.onload = function(e){
            create_transcript_text = e.target.result;
            if(create_transcript_text.match(/^file;unicode/)){
                create_transcript_tdf = create_transcript_text;
            }
            else if(create_transcript_text.match(/^\s*\[\s*\{/)){
                create_transcript_tdf = create_transcript_text;
            }
            else if(create_transcript_text.match(/^\s*\[\s*\{/)){
                create_transcript_jsonn = create_transcript_text;
            }
        }
        r.readAsText(create_transcript_files[0]);
    }
    function create_transcript_add(){
        create_transcript_auto = false;
        setTimeout( () => update_segments2(create_transcript_json), 100 );
    }
    function create_transcript_add_blanks(){
        create_transcript_auto = false;
        setTimeout( () => update_segments2_with_blanks(create_transcript_json), 100 );
    }
    function ch2docid(ch){
       return ch == 'B' ? docids[1] : docids[0];
    }
    // Skip the dialog entirely and apply one choice directly, resolving the
    // transcript the same way create_transcript_retrieve2 does (only tsv is wired).
    export function auto_import(mode){
        const o = ldc.maino;
        if(!(o && o.transcript)){
            setTimeout( () => auto_import(mode), 500 );
            return;
        }
        o.transcript.then( (x) => {
            let json = null;
            if(x.use_transcript == 'tsv') json = parse_tsv0(x.found_transcript);
            if(!json) return;
            if(mode == 'readonly')     update_segments2(json);
            else if(mode == 'blanks')  update_segments2_with_blanks(json);
            else if(mode == 'save')    add_save_asr(json, ch2docid('A'), () => window.location.reload());
        } );
    }
    function create_transcript_add_save(){
        create_transcript_auto = false;
        const f = () => window.location.reload();
        add_save_asr(create_transcript_json, ch2docid('A'), f);
        // setTimeout( () => {
        //     add_timestamps2(json, update_segments);
        //     add_cb( () => {
        //         window.location.reload();
        //     });
        // }, 100 );
    }
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-4xl" title="Upload Transcript">
    {#snippet children({ dialog })}
        {#if autoloading}
            <div class="flex items-center justify-center p-8">
                <div class="text-center">
                    <Spinner />
                    <p class="mt-4 text-gray-600 font-medium">Loading Transcript...</p>
                </div>
            </div>
        {/if}
        <div class="overflow-auto">
            <div class="p-6 space-y-6">
                {#if data_set_id && data_set_file_name}
                    <div class="flex items-center justify-center p-6">
                        <div class="text-center">
                            <Spinner />
                            <p class="mt-3 text-gray-600 font-medium">Adding transcript...</p>
                        </div>
                    </div>
                {:else}
                    {#if !create_transcript_auto}
                        <div class="border-2 border-dashed border-gray-300 rounded-lg p-6 hover:border-indigo-400 transition">
                            <label class="cursor-pointer block text-center">
                                <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
                                    <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                                </svg>
                                <p class="mt-2 text-sm text-gray-600">
                                    <span class="font-semibold text-indigo-600">Click to upload</span> or drag and drop
                                </p>
                                <p class="mt-1 text-xs text-gray-500">TSV, TDF, or JSON format</p>
                                <input type="file" bind:files={create_transcript_files} class="hidden">
                            </label>
                        </div>
                    {/if}

                    {#if (create_transcript_files && create_transcript_files[0]) || create_transcript_auto}
                        <div class="space-y-4">
                            {#if create_transcript_json}
                                <div class="bg-green-50 border border-green-200 rounded-lg p-4">
                                    <div class="flex items-center mb-3">
                                        <svg class="h-5 w-5 text-green-600 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                                        </svg>
                                        <span class="text-green-800 font-medium">File parsed successfully</span>
                                    </div>
                                    <div class="flex gap-3">
                                        <button class="{btn} flex-1" onclick={create_transcript_add} data-close-dialog>Add Read Only</button>
                                        <button class="{btn} flex-1" onclick={create_transcript_add_blanks} data-close-dialog>Add with Blanks</button>
                                        {#if ldcPermissions.admin || create_transcript_auto}
                                            <button class="{btn} flex-1" onclick={create_transcript_add_save} data-close-dialog>Add and Save</button>
                                        {/if}
                                    </div>
                                </div>
                            {:else if create_transcript_text}
                                <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
                                    {#if create_transcript_tsv}
                                        <div class="flex items-center justify-between">
                                            <div class="flex items-center">
                                                <svg class="h-5 w-5 text-blue-600 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                                    <path d="M9 2a2 2 0 00-2 2v8a2 2 0 002 2h6a2 2 0 002-2V6.414A2 2 0 0016.414 5L14 2.586A2 2 0 0012.586 2H9z"/>
                                                    <path d="M3 8a2 2 0 012-2v10h8a2 2 0 01-2 2H5a2 2 0 01-2-2V8z"/>
                                                </svg>
                                                <span class="text-blue-800 font-medium">File appears to be TSV</span>
                                            </div>
                                            <button class="{btn}" onclick={() => create_transcript_json = parse_tsv(create_transcript_text)}>Parse as TSV</button>
                                        </div>
                                    {:else if create_transcript_tdf}
                                        <div class="flex items-center justify-between">
                                            <div class="flex items-center">
                                                <svg class="h-5 w-5 text-blue-600 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                                    <path d="M9 2a2 2 0 00-2 2v8a2 2 0 002 2h6a2 2 0 002-2V6.414A2 2 0 0016.414 5L14 2.586A2 2 0 0012.586 2H9z"/>
                                                </svg>
                                                <span class="text-blue-800 font-medium">File appears to be TDF</span>
                                            </div>
                                            <button class="{btn}" onclick={() => create_transcript_json = parse_tdf(create_transcript_text)}>Parse as TDF</button>
                                        </div>
                                    {:else if create_transcript_sad_with_aws}
                                        <div class="flex items-center justify-between">
                                            <div class="flex items-center">
                                                <svg class="h-5 w-5 text-blue-600 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                                    <path d="M3 12v3c0 1.657 3.134 3 7 3s7-1.343 7-3v-3c0 1.657-3.134 3-7 3s-7-1.343-7-3z"/>
                                                </svg>
                                                <span class="text-blue-800 font-medium">File appears to be JSON</span>
                                            </div>
                                            <button class="{btn}" onclick={() => create_transcript_json = parse_sad_with_aws(create_transcript_text)}>Parse as JSON</button>
                                        </div>
                                    {:else if create_transcript_jsonn}
                                        <div class="flex items-center justify-between">
                                            <div class="flex items-center">
                                                <svg class="h-5 w-5 text-blue-600 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                                    <path d="M3 12v3c0 1.657 3.134 3 7 3s7-1.343 7-3v-3c0 1.657-3.134 3-7 3s-7-1.343-7-3z"/>
                                                </svg>
                                                <span class="text-blue-800 font-medium">File appears to be JSON</span>
                                            </div>
                                            <button class="{btn}" onclick={() => create_transcript_json = JSON.parse(create_transcript_text)}>Parse as JSON</button>
                                        </div>
                                    {:else}
                                        <div class="flex items-center">
                                            <svg class="h-5 w-5 text-yellow-600 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                                            </svg>
                                            <span class="text-yellow-800 font-medium">Unknown format</span>
                                        </div>
                                    {/if}
                                </div>
                            {:else}
                                <div class="flex justify-center">
                                    <button class="{btn} px-8 py-3" onclick={create_transcript_upload}>Upload File</button>
                                </div>
                            {/if}
                        </div>
                    {/if}
                {/if}

                {#if create_transcript_json || create_transcript_text}
                    <div class="border-t border-gray-200 pt-6">
                        <h5 class="text-sm font-medium text-gray-700 mb-3">
                            {#if create_transcript_json}
                                Parsed Preview
                            {:else}
                                Original File Preview
                            {/if}
                        </h5>
                        <div class="bg-gray-50 rounded-lg p-4 max-h-64 overflow-auto">
                            {#if create_transcript_json}
                                <pre class="text-xs text-gray-800 font-mono">{#each create_transcript_json as x}{JSON.stringify(x) + "\n"}{/each}</pre>
                            {:else if create_transcript_text}
                                {#if create_transcript_tsv || create_transcript_tdf}
                                    <pre class="text-xs text-gray-800 font-mono">{create_transcript_text.split("\n").slice(0,9).join("\n")}</pre>
                                {:else if create_transcript_jsonn}
                                    <pre class="text-xs text-gray-800 font-mono">{create_transcript_text.substr(0,999)}</pre>
                                {:else if create_transcript_sad_with_aws}
                                    <pre class="text-xs text-gray-800 font-mono">{JSON.stringify(create_transcript_text).substr(0,999)}</pre>
                                {/if}
                            {/if}
                        </div>
                    </div>
                {/if}
            </div>
        </div>
    {/snippet}
</BaseDialog>
