<script>
    import { listObjectsV2params } from 'https://cdn.jsdelivr.net/gh/Linguistic-Data-Consortium/ldcjs@0.0.10/src/aws_helper.js';
    import { getp } from 'https://cdn.jsdelivr.net/gh/Linguistic-Data-Consortium/ldcjs@0.0.10/src/getp.js'
    import Table from '../lib/ldcjs/work/table.svelte';
    import Spinner from './spinner.svelte'
    import { btn } from "./buttons"
    import { get_open_tasks } from './browse_helper'
    export let help;
    export let admin = false;
    export let lead_annotator = false;
    let unused = help && admin && lead_annotator;
    export let bucket;
    export let p_for_bucket;

    let columns = [
        [ 'Key', 'Key', 'col-2' ],
        [ 'LastModified', 'LastModified', 'col-2' ],
        [ 'Size', 'Size', 'col-1' ]
    ];



    let error;
    let contents;
    let prefix = '';
    function list(){
        const params = {
            Bucket: bucket,
            Prefix: prefix
        };
        listObjectsV2params(params).then(res => {
            if(res.Contents){
                contents = res.Contents.map( obj => {
                    // console.log(obj)
                    return {Key:obj.Key, Size: obj.Size, LastModified: obj.LastModified}
                });
            }
            else{
                contents = [];
            }
        })
        .catch(e => error = e);
    }
    let object_id;
    let object_index;
    function create(task){
        // console.log(object_index);
        // console.log(open_tasks);
        let f = `s3://${bucket}/${object_id}`;
        let copen = 's3';
        let path = `/kits_new?${copen}=${f}&task_id=${task.task_id}&filename=${f}`
        let pp = getp(path);
        // console.log(path);
        pp.then( () => {
            contents = null;
            window.location = task.work_path;
        } ); 
    }
    let open_tasks = {};
    p_for_bucket.then( (x) => get_open_tasks(x, open_tasks) );
    let timeout;
    function update(x){
        contents = null;
        if(timeout) clearTimeout(timeout);
        timeout = setTimeout( () => list() , 1000 );
    }
    $: update(prefix);
</script>

<style>
</style>

{#if error}
    {error}
{/if}
<div class="flex justify-around w-full mb-4">
    <div class="grid grid-cols-2">
        <div>Bucket</div>
        <div>Prefix</div>
        <div>{bucket}</div>
        <div><input bind:value={prefix} class="border-black border-2" /></div>
    </div>
    {#await p_for_bucket}
        <div class="mx-auto w-8 h-8"><Spinner /></div>
    {:then v}
        {#if object_id}
            <div class="ml-4">
                {#each Object.values(open_tasks) as task}
                    <div class="mb-4">
                        <button
                            class="{btn} {task.has_kit ? 'hover:bg-red-500' : 'hover:bg-green-500'}"
                            on:click={() => create(task)}
                            disabled={task.has_kit ? true : false}
                        >
                            {#if task.has_kit}
                                Task {task.task} <br> (transcript {task.has_kit} is open)
                            {:else}
                                Create Transcript in Task {task.task}
                            {/if}
                        </button>
                    </div>
                {/each}
            </div>
        {/if}
    {/await}
</div>
<hr>
{#if contents}
    <Table bind:selected={object_id} indexf={x => object_index = x} {columns} rows={contents} use_filter={true} key_column=Key height="96" />
{:else}
    <div class="mx-auto w-8 h-8"><Spinner /></div>
{/if}
