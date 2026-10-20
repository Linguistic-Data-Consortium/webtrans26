<script>
    import { btn } from "./buttons"
    import { promise_bucket } from '../lib/ldcjs/service_config';
    import { getp } from 'https://cdn.jsdelivr.net/gh/Linguistic-Data-Consortium/ldcjs@0.0.9/src/getp.js'
    import Help from './help.svelte'
    import Table from '../lib/ldcjs/work/table.svelte';
    import Bucket from './bucket.svelte'
    import PromiseBucket from './promise_bucket.svelte'
    import { selectedff } from './helpers';
    /**
     * @typedef {Object} Props
     * @property {any} help
     * @property {boolean} [admin]
     * @property {boolean} [lead_annotator]
     * @property {boolean} [portal_manager]
     * @property {boolean} [project_manager]
     * @property {any} p_for_bucket
     */

    /** @type {Props} */
    let {
        help,
        admin = false,
        lead_annotator = false,
        portal_manager = false,
        project_manager = false,
        p_for_bucket
    } = $props();
    let unused = portal_manager && project_manager;
    let category;
    let name;
    // let p = $state();
    // function get(){ p = getp('/bucket') }
    // get();
    // `p` is the in-flight Promise for the bucket list — it's set once and
    // the {#await p} block consumes it directly, so it doesn't need to be
    // reactive state. Declaring it as $state triggered a Svelte warning
    // about reading the initial value in this same scope.
    let p = getp('/bucket');
    let columns = [
        [ 'Bucket', 'name', 'col-1' ]
    ];
    let bucket_name = $state();
    let bucket_index = $state();
    p.then( (o) => {
			console.log("does this still need to happen?");
			console.log(o);
    });
    let bucket = $state();
    let style = $state();
    let selectedf = selectedff(x => style = x);
</script>

<style>
</style>

<Help {help}>
    {#snippet content()}
    <div>
        <p>features</p>
    </div>
    {/snippet}
</Help>

{#await p}
    loading...
{:then v}
    {#if bucket}
        <div class="flexx justifxy-around">
            <div class="float-right">
                <button class="{btn}" onclick={()=>bucket=null}>Return to Bucket list</button>
            </div>
        </div>
        {#if bucket == 'proimse-uploads'}
            <Bucket {help} {admin} {lead_annotator} {bucket} {p_for_bucket} />
        {:else}
            <PromiseBucket {help} {admin} {lead_annotator} {bucket} {p_for_bucket} />
        {/if}
    {:else}
        <div class="w-1/2 mx-auto">
            <div class="flex justify-around">
                <div>
                    <button class="{btn}" onclick={()=>bucket=bucket_name}>Open</button>
                </div>
                <div>
                    {#if promise_bucket()}
                        <button class="{btn}" onclick={()=>bucket=promise_bucket()}>Open Promises</button>
                    {/if}
                </div>
            </div>
            {#if style}
                <div {style}>
                    <div class="p-1"><button class="{btn}" onclick={()=>bucket=bucket_name}>Open</button></div>
                </div>
            {/if}
            <Table bind:selected={bucket_name} indexf={x => bucket_index = x} {columns} rows={v.buckets} use_filter={true} key_column=name height=96 {selectedf} />
        </div>
    {/if}
{/await}
