<script>
    import { sado, asro } from './asr.svelte';
    import Spinner from '../work/spinner.svelte';
    let {
    } = $props();

    // let ok = true;
    // $effect(() => {
    //     console.log('once')
    //     if(p4 && ok){
    //         ok = false;  // this is necessary, but why?  p4 is modified somehow?
    //         xasrr(p4);
    //     }
    // });

    let p1 = $state();
    let p2 = $derived(sado.pending_promise);
    let p3 = $derived.by(() => {
        return asro.pending_promise?.then((x) => {
            // cb();
            // f();
            // return JSON.stringify(x);
            p4 = true;
            m4 = x;
            // return new Promise((x,y) => {});
        });
    });
    // let p4 = $derived(p3.then(xasrr));
    let p4 = $state();
    let m1 = $state();
    let m2 = $derived(sado.status == 'pending' ? `running sad... (channel ${sado.i})` : '');
    let m3 = $derived(asro.status == 'pending' ? `running asr... (channel ${asro.i})` : '');
    // 'unavailable' means this instance never configured the service, which is
    // a normal state for an install that only needs manual transcription — so
    // this says so plainly rather than reporting an error.
    let unavailable = $derived(sado.status == 'unavailable' || asro.status == 'unavailable');
    let m4 = $state();

</script>

<div class="w-full mx-auto">
    {#if unavailable}
        <div class="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
            Speech activity detection and ASR are not configured on this server,
            so they are unavailable. Everything else works as normal.
        </div>
    {/if}
    {#if p1}
        {#await p1}
            <Spinner />
            {m1}
        {:then v}
            <!-- adding {v.length} segments -->
            using {v}
        {:catch e}
            <div>error</div>
            <div>{e}</div>
        {/await}
    {/if}
    <hr>
    {#if p2}
        {#await p2}
            <Spinner />
            {m2}
        {:then v}
            {#if v && v.ch1 && v.ch1.length}
                <div> adding {v.ch1.length} segments from channel 1</div>
            {/if}
            {#if v && v.ch2 && v.ch2.length}
                <div> adding {v.ch2.length} segments from channel 2</div>
            {/if}
        {:catch e}
            <div>error</div>
            <div>{e}</div>
        {/await}
    {/if}
    <hr>
    {#if p3}
        {#await p3}
            <Spinner />
            {m3}
        {:then v}
            <!-- <Spinner /> -->
            <div>{v}</div>
        {:catch e}
            <div>error</div>
            <div>{e}</div>
        {/await}
    {/if}
    <hr>
    {#if p4}
        <!-- <span class="border">{p4.result.items.length} ASR items</span> -->
        {#key asro.addedn}
            {#if asro.addedn > -1}
                <span class="border">added {asro.addedn} of {asro.vvsegs.length} ASR segments (channel {asro.i})</span>
            {:else}
                <!-- <button id="xasrb2" class="{btn}" on:click={xasrr}>add ASR segments</button> -->
            {/if}
        {/key}
    {/if}
</div>

<style>
</style>
