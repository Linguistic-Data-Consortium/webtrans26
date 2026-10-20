<script>
    import { createEventDispatcher } from 'svelte';
    const dispatch = createEventDispatcher();
    let {
        playheadtext,
        wave_selection_src,
        refocus,
        fmap2,
        help_screen_mini_css
    } = $props();
    let help_screen_hidden = $state(true);
    let help_screen_mini = $state();
    let help_screen_list = $state([]);
    let help_screen_title = $state('TITLE');
    let help_screen_keyboard;
    let help_screen_remove;
    let help_screen_reset;
    let help_screen_html = $state();
    let help_screen_screen;
    let help_screen_map;
    let help_screen_delegate;
    let help_screen_resolvef;
    export function help_screen_open(h){
        help_screen_hidden = false;
        help_screen_title = h.title;
        help_screen_keyboard = h.keyboard;
        help_screen_list = h.list;
        help_screen_remove = h.remove;
        help_screen_reset = h.reset;
        help_screen_html = h.html;
        help_screen_mini = h.mini;
        help_screen_map = h.map;
        help_screen_delegate = h.delegate;
        if(help_screen_map == 'delegate' && !help_screen_list){
            help_screen_map = help_screen_delegate.get_map();
            help_screen_list = [];
            for(let k in help_screen_map) help_screen_list.push([k, help_screen_map[k]]);
        }
        setTimeout(function(){
            help_screen_screen.focus();
        }, 100);
        return new Promise( (resolve, reject) => help_screen_resolvef = resolve );
    }
    function help_screen_keydown(e){
        e.preventDefault();
        if(help_screen_remove){
            help_screen_hidden = true;
        }
        if(help_screen_reset){
            refocus();
        }
        if(help_screen_keyboard){
            const f = help_screen_keyboard.handle(e, help_screen_mini);
            if(f === 'close') help_screen_hidden = true;
            else if(f)        help_screen_resolvef(f());
        }
        else{
            const userf = fmap2(help_screen_delegate, e, help_screen_map);
            // console.log(userf)
            if(userf){
                // dispatch('userf', { userf: userf, e: e } )
                if(userf === 'close') help_screen_hidden = true;
                if(userf === 'none'){
                    help_screen_hidden = true;
                    refocus();
                    dispatch('none');
                }
            }
        }
    }
</script>
<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div bind:this={help_screen_screen} class="p-2 {help_screen_mini ? help_screen_mini_css : ''}" class:hidden={help_screen_hidden} tabindex=0 onkeydown={help_screen_keydown}>
    <div>
        {#if help_screen_html}
            {#if help_screen_html == 'help_screen_playback_html'}
                <!-- <div>Playhead: {playheadtext}</div>
                <div>Selection: {wave_selection_src.beg} {wave_selection_src.end}</div> -->
                <ol>
                    <li>
                        - <b>s</b> stop
                    </li>
                    <li>
                        - <b>c</b> play from cursor
                    </li>
                    <li>
                        - <b>[</b> play from beginning of selection
                    </li>
                    <li>
                        - <b>]</b> play from end of selection
                    </li>
                    <li>
                        - <b>.</b> center segment and play
                    </li>
                </ol>
            {:else}
                {@html help_screen_html}
            {/if}
        {:else}
           <div>
                {#if help_screen_title}
                    <h3 class="text-xl mb-1">{help_screen_title}</h3>
                {/if}
                <ul>
                    {#each help_screen_list as x}
                        <li class="mb-1"><span class="font-sans font-semibold uppercase text-gray-300">{x[0]}</span> {x[1]}</li>
                    {/each}
                </ul>
                <div class="text-xs">press any other key to exit</div>
            </div>
        {/if}
    </div>
</div>
