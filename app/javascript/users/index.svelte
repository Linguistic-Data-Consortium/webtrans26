<script>
    import { getp } from '../lib/ldcjs/getp'
    import Table from '../lib/ldcjs/work/table.svelte';
    export const admin = false;
    let p = getp(window.location);
    let columns = [
        [ 'ID', 'id', 'col-1' ],
        [ 'Name', 'name', 'col-2' ],
        [ 'Edit', 'edit', 'col-1', 'html' ],
        [ 'Reset Name', 'reset', 'col-1', 'html' ],
        [ 'Delete', 'delete', 'col-1', 'html' ]
    ];
    p.then(function(x){console.log(x)});
</script>

<style>
</style>

<div>
    {#await p}
        loading...
    {:then v}
        <Table {columns} rows={v} use_filter={true} key_column=id height=500 />
    {/await}
</div>
