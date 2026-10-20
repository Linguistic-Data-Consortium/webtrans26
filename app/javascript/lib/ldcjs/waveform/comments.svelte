<script>
    // Remarks about stretches of audio, in their own list under the
    // transcript. A comment is a span with one label and nothing else — no
    // speaker, no section, no place in any transcript export — so it gets its
    // own panel rather than a row among the segments the annotator types into.
    //
    // Kept deliberately plain, like sections.svelte: a time, the text, and a
    // way to remove it.
    import { onDestroy } from 'svelte';
    import { btn, dbtn } from '../work/buttons';
    import { transcript } from './transcript.svelte';
    import { pad } from './helpers';

    let {
        add_comment,
        set_comment_text,
        delete_comment,
        // The comment just made — its input takes focus, so a comment can be
        // written without reaching for the mouse.
        focus_iid = null,
        play_span = null
    } = $props();

    const rows = $derived(transcript.comments);

    // Written a second after the typing stops, the way a segment's text is
    // (t_update / t_patch in segments.svelte) — a message per keystroke would
    // be a message per keystroke. Blur and Enter flush what's pending rather
    // than waiting out the second.
    //
    // Per row rather than per component: the panel shows every comment at
    // once, so two can be part-typed where a segment's textarea is one at a
    // time.
    const DEBOUNCE = 1000;
    const timers = new Map();   // iid -> pending write
    const drafts = $state(new Map());   // iid -> what's in the box

    // What the box shows: the draft while one is in hand, the row otherwise.
    // The draft is dropped once the row catches up — the write goes through
    // the log and comes back through the graph, so until it does, the row
    // still holds the old text and rendering it would undo the typing.
    const shown = (row) => (drafts.has(row.iid) ? drafts.get(row.iid) : row.text);
    $effect(() => {
        for(const row of rows){
            if(drafts.get(row.iid) === row.text) drafts.delete(row.iid);
        }
    });

    function typed(row, value){
        drafts.set(row.iid, value);
        if(timers.has(row.iid)) clearTimeout(timers.get(row.iid));
        timers.set(row.iid, setTimeout( () => write(row), DEBOUNCE ));
    }

    function write(row){
        if(timers.has(row.iid)){
            clearTimeout(timers.get(row.iid));
            timers.delete(row.iid);
        }
        if(!drafts.has(row.iid)) return;
        set_comment_text(row, drafts.get(row.iid));
    }

    // Nothing half-typed is lost when the panel goes away.
    onDestroy( () => {
        for(const iid of [ ...timers.keys() ]){
            const row = rows.find( (r) => r.iid === iid );
            if(row) write(row);
        }
    } );

    function keydown(e, row){
        if(e.key === 'Enter'){
            e.preventDefault();
            e.stopPropagation();
            e.target.blur();
        }
        else if(e.key === 'Escape'){
            if(timers.has(row.iid)) clearTimeout(timers.get(row.iid));
            timers.delete(row.iid);
            drafts.delete(row.iid);
            e.target.blur();
        }
        else {
            // The waveform's key handlers listen on the window; a comment
            // being typed isn't a command.
            e.stopPropagation();
        }
    }
    function focus_new(node, iid){
        if(iid != null && iid === focus_iid) node.focus();
        return {};
    }
</script>

<section id="comments" class="mt-4 border-t border-gray-200 pt-3">
    <div class="flex items-center justify-between mb-2">
        <div class="font-medium text-sm text-gray-700">
            Comments {rows.length ? `(${rows.length})` : ''}
        </div>
        <button type="button" class="{btn}" onclick={add_comment}>
            Comment on selection
        </button>
    </div>

    {#if rows.length === 0}
        <div class="text-xs text-gray-500">
            Nothing yet. Select a stretch of audio — or a segment — and use
            <span class="font-medium">Comment on selection</span>.
        </div>
    {:else}
        <div class="text-sm font-mono">
            {#each rows as row, i (row.iid)}
                <div class="grid grid-cols-12 gap-2 items-center py-0.5 {i % 2 ? 'bg-gray-50' : ''}">
                    <button
                        type="button"
                        class="col-span-2 text-left text-xs text-gray-600 hover:text-indigo-600"
                        title="play this span"
                        onclick={() => play_span && play_span(row)}
                    >{pad(row.beg)}–{pad(row.end)}</button>
                    <input
                        class="col-span-9 text-sm px-1 rounded border border-transparent hover:border-gray-300 focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
                        type="text"
                        value={shown(row)}
                        placeholder="a note about this stretch"
                        oninput={(e) => typed(row, e.target.value)}
                        onblur={() => write(row)}
                        onkeydown={(e) => keydown(e, row)}
                        use:focus_new={row.iid}
                    />
                    <div class="col-span-1 text-right">
                        <button type="button" class="{dbtn}" onclick={() => delete_comment(row)}>×</button>
                    </div>
                </div>
            {/each}
        </div>
    {/if}
</section>
