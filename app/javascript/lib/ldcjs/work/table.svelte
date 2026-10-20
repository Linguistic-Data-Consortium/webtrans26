<script>
    import { create_download_tsv, create_download_url } from '../download_helper';
    import { btn } from './buttons';
    export let columns;
    export let rows;
    export let use_filter = true;
    export let key_column = "id";
    export let height = "400";
    export let column_border = false;
    export let download = false;
    export function get_selected_key(){
        return selected;
    }
    export function make_copy(table, map, key1, key2){
        let a = [];
        for(let x of table){
            let h = {};
            a.push(h);
            for(let y in x){
                h[y] = x[y];
            }
            if(map){
                let v = h[key2];
                if(v){
                    v = map[v];
                    if(v) h[key1] = v;
                }
            }
        }
        return a;
    }
    export let selectedf;
    let sorti = -1;
    let sortd = true;
    let sort_key;
    function sort3(a, b){
        return sort1(a[sort_key].replace(/<.+?>/g, ''), b[sort_key].replace(/<.+?>/g, ''));
    }
    function sort2(a, b){
        return sort1(a[sort_key], b[sort_key]);
    }
    function sort1(a, b){
        return sort4(String(a).toLowerCase(), String(b).toLowerCase());
    }
    function sort4(a, b){
        if(a < b){
            if(sortd) return -1;
            else      return 1;
        }
        if(a > b){
            if(sortd) return 1;
            else      return -1;
        }
        return 0;   
    }
    function header(){
        let i = this.dataset.i;
        if(i == sorti){
            sortd = ! sortd;
        }
        else{
            sorti = i;
            sortd = true;
        }
        if(sorti > -1){
            sort_key = columns[sorti][1];
            let c = make_copy(rows);
            if(columns[sorti][3] == 'html') c.sort(sort3);
            else                            c.sort(sort2);
            rows = c;
        }
        else{
        }
    }
    export let selected = null;
    function click_select(e){
        selected = this.dataset.key;
        selectedf(selected, e);
    }
    let text_red;
    export function set_text_red(x){
        text_red = x;
    }
    let filter = '';
    let matched = [];
    function match(x, i){
        if(i == 0) matched = [];
        let b = match3(x);
        if(b) matched.push(x);
        return b;
    }
    function match3(x){
        if(filter == '') return match2(x);
        let re = new RegExp(filter, 'i');
        for(let i = 0; i < columns.length; i++){
            let k = columns[i][1];
            if(x[k] && String(x[k]).match && String(x[k]).match(re)) return match2(x);
        }
        return false;
    }
    let index = {};
    export let indexf = () => null;
    indexf(index);
    if(key_column){
        for(let x of rows){
            index[x[key_column]] = x;
        }
    }
    // indexf(index);
    let use_menu_filters = false;
    let filters = {};
    let all = {}
    for(let x of columns){
        if(x[3] == 'filter'){
            use_menu_filters = true;
            filters[x[1]] = 'any';
            all[x[1]] = [ 'any' ];
        }
    }
    function handleSubmit(){}
    for(let x of rows){
        for(let y of columns){
            let key = y[1];
            if(y[3] == 'filter'){
                if(!all[key].includes(x[key])){
                    all[key].push(x[key]);
                }
            }
        }
    }
    function match2(x){
        for(let y of columns){
            let key = y[1];
            if(y[3] == 'filter'){
                if(filters[key] != 'any' && x[key] != filters[key]){
                    return false;
                }
            }
        }
        return true;
    }
    export function match_attempted(){
        for(let y of columns){
            let key = y[1];
            if(y[3] == 'filter'){
                if(filters[key] != 'any'){
                    return true;
                }
            }
        }
        return filter.length > 0;
    }
    export function get_matched(){
        return matched;
    }
    let tsv;
    let include_headers;
    let include_full;
    let url;
    let link;
    let filename;
    function download_reset(){
        tsv = 'empty';
        include_headers = false;
        include_full = null;
        url = null;
    }
    function downloadf(){
        tsv = create_download_tsv(rows, columns, include_headers, include_full, matched);
        url = create_download_url(tsv);
        link.href = url;
    }
    // The download panel is a plain <details>: the summary is the toggle, and
    // everything below it is the "dialog". Closing means clearing details.open —
    // the backdrop, the ✕ and Escape all come back here.
    let download_details;
    function download_close(){
        if(download_details) download_details.open = false;
    }
    function download_keydown(e){
        if(e.key == 'Escape' && download_details && download_details.open) download_close();
    }
</script>

<style>
    .odd {
      background: #eee;
    }
    #preview {
        width: 100%;
        height: 200px;
        overflow: auto;
    }
    /* <details> shows a disclosure triangle next to the summary by default;
       the summary here is a styled button, so hide the marker. */
    summary.download-summary {
        list-style: none;
    }
    summary.download-summary::-webkit-details-marker {
        display: none;
    }
</style>


<svelte:window on:keydown={download_keydown} />

<div>
    {#if use_filter}
        <div class="flex justify-around">
            <div class="float-left">
                {rows.length} row{rows.length == 1 ? '' : "s"}
            </div>
            {#if download}
                <div class="float-right">
                    <details bind:this={download_details}>
                        <summary class="download-summary {btn}" onclick={download_reset} title="Download table as a file">
                            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 inline-block align-text-bottom" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                                <path fill-rule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM6.293 8.293a1 1 0 011.414 0L9 9.586V3a1 1 0 112 0v6.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clip-rule="evenodd" />
                            </svg>
                            <span class="ml-1">Download</span>
                        </summary>
                        <!-- Backdrop: dims the page and closes the panel on click. -->
                        <!-- svelte-ignore a11y_click_events_have_key_events -->
                        <!-- svelte-ignore a11y_no_static_element_interactions -->
                        <div class="fixed inset-0 z-40 bg-black/50" onclick={download_close}></div>
                        <div class="fixed left-1/2 top-[10vh] z-50 w-[44rem] max-w-[90vw] max-h-[80vh] overflow-auto -translate-x-1/2 rounded-lg border border-gray-300 bg-white text-left shadow-xl">
                            <div class="flex items-center justify-between border-b border-gray-200 px-4 py-3">
                                <h3 class="text-lg font-medium">Download Table as File</h3>
                                <button class="px-2 text-xl leading-none text-gray-500 hover:text-gray-800" type="button" aria-label="Close dialog" onclick={download_close}>&times;</button>
                            </div>
                            <div class="px-4 py-3">
                                <div>
                                    <p>You can download the full table or a filtered form of it as a tab separated file.</p>
                                    <p>Note that the original ordering of the table isn't saved once you sort the table by clicking the column headers.  If you've sorted the table, that's the "full" form.</p>
                                </div>
                                <form class="my-3 flex flex-wrap items-center justify-around gap-2">
                                    <label>
                                        <input type=radio bind:group={include_full} value=yes >
                                        Full Table
                                    </label>
                                    <label>
                                        <input type=radio bind:group={include_full} value=no  >
                                        Matched Rows Only
                                    </label>
                                    <label>
                                        <input type=checkbox bind:checked={include_headers}>
                                        Include headers
                                    </label>
                                    <label>
                                        <input class="input-sm rounded-md border-2 border-gray-300" type=text bind:value={filename} placeholder="filename">
                                    </label>
                                    <!-- svelte-ignore a11y_missing_attribute -->
                                    <a class="text-blue-600 underline hover:text-blue-800" bind:this={link} download={filename}>{ url ? "Download" : ""}</a>
                                    {#if !url}
                                        <button type="button" class="{btn}"   onclick={downloadf}>Create</button>
                                    {/if}
                                </form>
                                <div>Preview</div>
                                <pre id="preview" class="border">{tsv}</pre>
                            </div>
                        </div>
                    </details>
                </div>
            {/if}
            <div class="float-right">
                <span>{matched.length} matched</span>
                <input
                    class="m-3 focus:ring-indigo-500 focus:border-indigo-500 rounded-md border-gray-300 border-2"
                    bind:value={filter}
                    placeholder="filter"
                >
            </div>
            {#if use_menu_filters}
                <div class="float-right px-4">
                    <div>
                        {#each columns as x}
                            {#if x[3] == 'filter'}
                                <div class="flex">
                                    {x[0]}
                                    {filters[x[1]]}
                                    <select
                                        class="ml-4 focus:ring-indigo-500 focus:border-indigo-500 flex-1 block w-full rounded-md border-gray-300"
                                        bind:value={filters[x[1]]}
                                    >
                                        {#each all[x[1]] as y}
                                            <option value={y}>{y}</option>
                                        {/each}
                                    </select>
                                </div>
                            {/if}
                        {/each}
                    </div>
                </div>
            {/if}
        </div>
    {/if}
    <div class="clear-both overflow-y-auto h-{height}">
    <table class="relative w-full">
        <thead>
        <tr>
            {#each columns as x, i}
                <th class="sticky top-0 text-left {x[2]} p-2 {i == sorti ? 'bg-yellow-100' : 'bg-blue-100'}"
                onclick={header} data-i={i} data-col={x[1]}>
                    <div class="flex">
                        {x[0]}
                        {#if sorti == i}
                            {#if sortd}
                                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                                  <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
                                </svg>
                            {:else}
                                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                                  <path fill-rule="evenodd" d="M14.707 12.707a1 1 0 01-1.414 0L10 9.414l-3.293 3.293a1 1 0 01-1.414-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 010 1.414z" clip-rule="evenodd" />
                                </svg>
                            {/if}
                        {/if}
                    </div>
                </th>
            {/each}
        </tr>
        </thead>
        <tbody>
        {#each rows as x, i}
            {#if match(x, i) && filter.length > -1 && filters}
                <tr class="

                    {x[key_column] == selected ? 'bg-green-100': '' }
                    {x[key_column] == text_red ? 'bg-red-100': '' }
                    {i % 2 ? 'oddd' : ''}
                "
                onclick={click_select} data-key={x[key_column]} data-hintable>
                    {#each columns as y, i}
                        <td class="{y[2]} p-2 break-word {column_border ? "border-x" : ""}" data-col={y[1]}>
                            {#if y[3] == 'html'}
                                {@html x[y[1]]}
                            {:else if y[3] == 'button'}
                                <button class="{btn}" title={x[y[1]]}>{x[y[1]]}</button>
                            {:else if y[3] == 'f'}
                                <!-- svelte-ignore a11y-no-static-element-interactions -->
                                <!-- svelte-ignore a11y-click-events-have-key-events -->
                                <div onclick={ () => y[4](x, y[1]) }>{x[y[1]]}</div>
                            {:else if x[y[1]]}
                                {x[y[1]]}
                            {:else}
                                <i>empty</i>
                            {/if}
                        </td>
                    {/each}
                </tr>
            {/if}
        {/each}
        </tbody>
    </table>
    </div>
</div>
