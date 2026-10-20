<script>
    import { graph as graph_state } from './transcript.svelte';

    // Shows the annotation graph the kit holds: time anchors, the labelled
    // spans between them, and the labels themselves. Sits under the transcript
    // so it can be read against it. Deliberately raw — the point is to inspect
    // the structure, not to re-render the transcript in a second style.
    //
    // The rows come from the shared state, which the payload fills on load and
    // Rebuild replaces with what the snapshot tables hold.
    let {
        loading = false,
        error = null,
        onRefresh = null,
        onHide = null,
        btn = ""
    } = $props();

    const graph = graph_state; // a proxy: reads of its fields below are reactive
    const empty = $derived(graph.nodes.length === 0 && graph.arcs.length === 0);
    // Arcs point at anchors rather than carrying times, so resolve them for
    // display — otherwise the span column would say nothing.
    const anchor_time = $derived(new Map(graph.nodes.map( (n) => [ n.iid, n.time ] )));

    const time = (t) => (t === null || t === undefined ? '' : Number(t).toFixed(3));
</script>

<section class="mt-6 border-t border-gray-300 pt-4">
    <div class="flex items-center justify-between mb-2">
        <div class="font-medium">Annotation graph</div>
        <div class="flex gap-2">
            <button type="button" onclick={onRefresh} class="{btn}" disabled={loading}>Rebuild</button>
            <button type="button" onclick={onHide} class="{btn}">Hide</button>
        </div>
    </div>
    <div class="max-h-96 overflow-auto">
            {#if loading}
                <div class="text-gray-600">Building…</div>
            {:else if error}
                <div class="text-red-600">{error}</div>
            {:else if empty}
                <div class="text-gray-600">Nothing annotated yet — no anchors, no spans.</div>
            {:else}
                <div class="mb-4 text-sm text-gray-600">
                    {#if graph.source === 'snapshot'}
                        Read back from graph_nodes / graph_arcs / graph_labels, rebuilt from this
                        kit's annotations just now.
                    {:else if graph.source === 'live'}
                        Maintained message by message as you annotate — this is what the transcript
                        above is rendered from.
                    {:else}
                        Unfolded here from the payload this kit loaded with — the same flat nodes
                        and values the tool has always been sent.
                    {/if}
                    One anchor or span per add message; one label per thing said about a span.
                </div>

                <div class="mb-2 font-medium">graph_nodes ({graph.nodes.length})</div>
                <table class="w-full mb-6 text-sm font-mono">
                    <thead>
                        <tr class="bg-blue-100 text-left">
                            <th class="p-1">iid</th>
                            <th class="p-1">time</th><th class="p-1">docid</th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each graph.nodes as n, i}
                            <tr class={i % 2 ? 'bg-gray-100' : ''}>
                                <td class="p-1">{n.iid}</td>
                                <td class="p-1">{time(n.time)}</td>
                                <td class="p-1 truncate" title={n.docid}>{n.docid ?? ''}</td>
                            </tr>
                        {/each}
                    </tbody>
                </table>

                <div class="mb-2 font-medium">graph_arcs ({graph.arcs.length})</div>
                <table class="w-full mb-6 text-sm font-mono">
                    <thead>
                        <tr class="bg-blue-100 text-left">
                            <th class="p-1">iid</th><th class="p-1">name</th>
                            <th class="p-1">beg→end</th>
                            <th class="p-1">time</th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each graph.arcs as a, i}
                            <tr class={i % 2 ? 'bg-gray-100' : ''}>
                                <td class="p-1">{a.iid}</td>
                                <td class="p-1">{a.name}</td>
                                <td class="p-1">{a.beg_iid ?? ''}→{a.end_iid ?? ''}</td>
                                <td class="p-1 whitespace-nowrap">{time(anchor_time.get(a.beg_iid))}–{time(anchor_time.get(a.end_iid))}</td>
                            </tr>
                        {/each}
                    </tbody>
                </table>

                <div class="mb-2 font-medium">graph_labels ({graph.labels ? graph.labels.length : 0})</div>
                <table class="w-full text-sm font-mono">
                    <thead>
                        <tr class="bg-blue-100 text-left">
                            <th class="p-1">iid</th><th class="p-1">arc</th>
                            <th class="p-1">name</th><th class="p-1">value</th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each (graph.labels ?? []) as l, i}
                            <tr class={i % 2 ? 'bg-gray-100' : ''}>
                                <td class="p-1">{l.iid}</td>
                                <td class="p-1">{l.arc_iid}</td>
                                <td class="p-1">{l.name}</td>
                                <td class="p-1">{l.value ?? ''}</td>
                            </tr>
                        {/each}
                    </tbody>
                </table>
            {/if}
    </div>
</section>
