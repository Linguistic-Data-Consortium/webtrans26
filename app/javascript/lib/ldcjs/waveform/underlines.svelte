<script>
    import { event } from '../../../guides/guide';
    import { activeo, sourceso, sourcesor } from './shared.svelte';
    let {
        i,
        docids,
        width,
        mousemove_underlines,
        underline,
        u
    } = $props();
    let debug = false;
    let draw_underlines_flag = $state(true);
    let underline_height = $state(5);
        //this function draws the underlines for a given line
    let underlines = $state([{}]);
    function underlinef(x){
        activeo.underline = x;
        console.log(x)
    }
</script>

{#if draw_underlines_flag}
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="underlines{i} relative" style="height: {u.height}px" onmousemove={mousemove_underlines} >
        {#each u.a as x}
            <div
                class="{x.class} absolute bg-blue-700"
                style="left: {x.x}px; top: {x.y}px; width: {x.width}px; height: {underline_height}px"
                onclick={() => underlinef(x)}
                onkeypress={() => null}
                use:event.dispatch={'drew_underline'}
            ></div>
        {/each}
    </div>
{/if}
