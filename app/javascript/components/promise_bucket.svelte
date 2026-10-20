<script>
    import { refreshToken, getSignedUrlPromise, putObject, s3url } from '../lib/ldcjs/aws_helper.js';
    import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
    import { fromCognitoIdentity } from "@aws-sdk/credential-provider-cognito-identity";
    import { CognitoIdentityClient } from "@aws-sdk/client-cognito-identity";
    import { TranscribeClient } from "@aws-sdk/client-transcribe";
    import { S3Client, GetObjectCommand, HeadObjectCommand, ListObjectsV2Command, PutObjectCommand } from "@aws-sdk/client-s3";
    // import { listObjectsV2params, getObject } from 'https://cdn.jsdelivr.net/gh/Linguistic-Data-Consortium/ldcjs@0.0.10/src/aws_helper.js';
    import { listObjectsV2params, getObject } from '../lib/ldcjs/aws_helper.js';
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

    refreshToken({
        fromCognitoIdentity,
        CognitoIdentityClient,
        TranscribeClient,
        S3Client,
        GetObjectCommand,
        HeadObjectCommand,
        ListObjectsV2Command,
        PutObjectCommand,
        getSignedUrl
    });


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
    function open(){
        getObject(bucket, object_id)
        .then((x) => x.Body)
        .then( (x) => x.transformToString())
        .then(JSON.parse)
        .then( (data) => {
            console.log(data);
        } )
        // const params = {
        //     Bucket: bucket,
        //     Prefix: object_id
        // };
        // listObjectsV2params(params).then(res => {
        //     if(res.Contents){
        //         contents = res.Contents.map( obj => {
        //             // console.log(obj)
        //             return {Key:obj.Key, Size: obj.Size, LastModified: obj.LastModified}
        //         });
        //     }
        //     else{
        //         contents = [];
        //     }
        // })
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
    let object = '';
</script>

<style>
</style>

{#if object}
    <div>{object}</div>
{/if}

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
                <div class="mb-4">
                    <button
                        class="{btn}"
                        on:click={() => open()}
                    >
                        Open
                    </button>
                </div>
            </div>
        {/if}
    {/await}
</div>
<hr>
{#if contents}
    <Table bind:selected={object_id} indexf={x => object_index = x} {columns} rows={contents} use_filter={true} key_column=Key height="96" selectedf={() => null} />
{:else}
    <div class="mx-auto w-8 h-8"><Spinner /></div>
{/if}
