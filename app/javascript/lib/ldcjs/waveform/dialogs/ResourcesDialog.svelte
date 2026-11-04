<script>
    // What this app keeps in the browser, and the controls for it: whatever is
    // registered as downloadable (resources/ — the speech model and runtime,
    // and any optional WASM module), the speech model choice, the local-audio
    // file handles, the per-browser settings, and whether the browser may
    // evict any of it. See resources/registry.js and stored_resources.js.
    //
    // The download list knows nothing about what it lists: a new module needs
    // only its registration. Read fresh each time it opens (refresh), since
    // the Worker and other tabs change what's stored without telling this page.
    import BaseDialog from './BaseDialog.svelte';
    import { btn, cbtn, dbtn } from '../../work/buttons';
    import { registered, rows_for, caches_used } from '../../resources';
    import {
        read_cache, delete_cache_files,
        storage_overview, keep_from_eviction, read_settings, reset_setting, format_bytes
    } from '../../stored_resources';
    import {
        ASR_SIZES, asr_model, server_model, chosen_size, choose_size, asr_language, server_language,
        choose_language, model_label, is_english_only, local_asr_available, single_pass_on, set_single_pass
    } from '../../local_asr';
    import { WHISPER_LANGUAGES, language_code, language_name } from '../../whisper_languages';
    import { close_asr_session } from '../segment_asr_run';
    import { forget_suggestions } from '../asr_preview.svelte';
    import { list_handles, handle_store } from '../../local_audio_handles';
    import { list_all_previews, clear_previews, span_layers } from '../span_layers.svelte';

    let { dialogRef = $bindable() } = $props();

    const asr_possible = local_asr_available();

    let overview = $state({ usage: null, quota: null, persisted: false, can_persist: false });
    let rows = $state([]);
    let handles = $state([]);
    let kept_previews = $state([]);
    let settings = $state([]);
    let model = $state(null);
    // The size buttons show the size of the model in use; the language field
    // what's typed, until it's a language Whisper knows.
    let size = $state(null);
    let language_text = $state('');
    let language_error = $state(null);
    let single_pass = $state(single_pass_on());
    let loading = $state(false);
    let error = $state(null);
    // Per row id: { pct } while downloading (pct null if the size isn't
    // known), { done: true }, or { error }.
    let progress = $state({});
    let persist_answer = $state(null);

    export async function refresh(){
        loading = true;
        error = null;
        try {
            model = asr_model();
            size = chosen_size() ?? /whisper-(tiny|base|small)/.exec(model)?.[1] ?? null;
            language_text = language_name(asr_language());
            language_error = null;
            settings = read_settings();
            const defs = registered();
            const entries = {};
            const [ o, h, p ] = await Promise.all([
                storage_overview(),
                list_handles().catch( () => [] ),
                list_all_previews().catch( () => [] ),
                ...caches_used(defs).map( async (name) => {
                    entries[name] = await read_cache(name).catch( (e) => {
                        error = `Couldn't read ${name}: ${e?.message || e}`;
                        return [];
                    } );
                } )
            ]);
            overview = o;
            handles = h;
            kept_previews = p;
            rows = rows_for(defs, entries);
        }
        finally {
            loading = false;
        }
    }

    // Another model or language: nothing should keep the old one warm, and
    // suggestions it made aren't the new one's.
    function changed(){
        model = asr_model();
        close_asr_session();
        forget_suggestions();
        settings = read_settings();
        refresh();
    }

    function choose(id){
        choose_size(id);
        changed();
    }

    // Typed or picked from the suggestions: a name, another name the library
    // knows, or a code. The server's own language, chosen here, is the same
    // as no choice.
    function choose_typed_language(){
        const code = language_code(language_text);
        if(!code){
            language_error = `Whisper doesn't know "${language_text}". Start typing a language's name to see the ones it does.`;
            return;
        }
        language_error = null;
        choose_language(code == server_language() ? null : code);
        language_text = language_name(code);
        changed();
    }

    async function download(row){
        progress[row.id] = { pct: 0 };
        try {
            await row.def.download(row.key, { onprogress: (p) => progress[row.id] = { pct: p } });
            progress[row.id] = { done: true };
        }
        catch(e){
            progress[row.id] = { error: e?.message || String(e) };
        }
        await refresh();
    }

    async function remove(row){
        const cache = row.def ? row.def.cache : row.key;
        await delete_cache_files(cache, row.files.map( (f) => f.url ));
        row.def?.on_delete?.(row.key);
        delete progress[row.id];
        await refresh();
    }

    async function forget_previews(kit){
        await clear_previews(kit);
        await refresh();
    }

    async function forget_handle(uid){
        await handle_store.delete(uid);
        await refresh();
    }

    async function forget_all_handles(){
        await handle_store.clear();
        await refresh();
    }

    function reset(key){
        reset_setting(key);
        if(key == 'asr_size' || key == 'asr_language') changed();
        settings = read_settings();
    }

    async function persist(){
        persist_answer = (await keep_from_eviction()) ? 'granted' : 'refused';
        await refresh();
    }

    const busy = (row) => progress[row.id] && !progress[row.id].done && !progress[row.id].error;
</script>

<BaseDialog bind:dialogRef={dialogRef} size="sm:max-w-3xl" title="Downloaded resources">
    {#snippet children({ dialog })}
        <div class="p-6 space-y-6 text-sm" data-testid="resources-dialog">
            <section>
                <h3 class="font-semibold text-gray-900 mb-1">Storage in this browser</h3>
                <p class="text-gray-700" data-testid="resources-usage">
                    {#if overview.usage != null}
                        This site uses {format_bytes(overview.usage)}{#if overview.quota}{' '}of the {format_bytes(overview.quota)} the browser allows it{/if}.
                    {:else}
                        This browser doesn't report how much is used.
                    {/if}
                </p>
                <div class="mt-2 flex items-center gap-3">
                    {#if overview.persisted}
                        <span class="text-green-700" data-testid="resources-persisted">Kept: the browser won't clear this to free space.</span>
                    {:else}
                        <span class="text-gray-600">The browser may clear this to free space.</span>
                        {#if overview.can_persist}
                            <button type="button" class={btn} onclick={persist} data-testid="resources-persist">Keep from eviction</button>
                        {/if}
                    {/if}
                </div>
                {#if persist_answer == 'refused'}
                    <p class="mt-1 text-xs text-amber-700">
                        The browser declined. Chrome grants this to sites used often or
                        installed; it may agree later.
                    </p>
                {/if}
            </section>

            {#if asr_possible}
            <section>
                <h3 class="font-semibold text-gray-900 mb-1">Speech recognition model</h3>
                <p class="text-gray-600 mb-2">
                    What recognition in this browser listens for. Your choices apply to
                    this browser only; download the model ahead below.
                </p>
                <div class="flex flex-wrap items-baseline gap-x-4 gap-y-1" role="radiogroup" aria-label="Model size">
                    {#each ASR_SIZES as z}
                        <label class="flex items-baseline gap-1.5" title={z.note}>
                            <input type="radio" name="asr-size" value={z.id} checked={size == z.id}
                                   onchange={() => choose(z.id)} data-testid={`resources-size-${z.id}`} />
                            <span class="text-gray-900">{z.label}</span>
                        </label>
                    {/each}
                </div>
                <p class="text-gray-500 text-xs mt-1">{ASR_SIZES.find( (z) => z.id == size )?.note ?? ''}</p>
                <label class="mt-3 block">
                    <span class="text-gray-900">Language</span>
                    <input type="text" list="whisper-languages" bind:value={language_text}
                           onchange={choose_typed_language}
                           onkeydown={(e) => { if(e.key === 'Enter'){ e.preventDefault(); choose_typed_language(); } }}
                           placeholder="Start typing: French, Spanish, ja…" autocomplete="off"
                           class="mt-1 block w-64 px-2 py-1 border border-gray-300 rounded" data-testid="resources-language" />
                    <datalist id="whisper-languages">
                        {#each WHISPER_LANGUAGES as [ code ]}<option value={language_name(code)}>{code}</option>{/each}
                    </datalist>
                </label>
                {#if language_error}<p class="mt-1 text-xs text-red-700" role="alert">{language_error}</p>{/if}
                <p class="mt-2 text-xs text-gray-600" data-testid="resources-model-in-use">
                    Runs <span class="font-mono">{model}</span>
                    — {model_label(model)}{#if !is_english_only(model)}, told it's hearing {language_name(asr_language())}{/if}.
                    {#if model == server_model() && asr_language() == server_language()}This server's default.{/if}
                </p>
                <label class="mt-3 flex items-baseline gap-2">
                    <input type="checkbox" checked={single_pass} data-testid="resources-single-pass"
                           onchange={(e) => { set_single_pass(e.currentTarget.checked); single_pass = single_pass_on(); settings = read_settings(); }} />
                    <span>
                        <span class="text-gray-900">One pass per window (experimental)</span>
                        <span class="block text-gray-500 text-xs">
                            For whole-file runs (Services 5). The model normally goes over the end
                            of a 30 s window again when it stops short of it; this skips that,
                            which was about a third of the time in one measured run. The next
                            window's overlap covers most of what's skipped, but speech where the
                            model stops early inside a window could be missed. The run's summary
                            says which way it ran.
                        </span>
                    </span>
                </label>
            </section>
            {/if}

            <section>
                <h3 class="font-semibold text-gray-900 mb-1">Downloads</h3>
                {#if error}<p class="text-red-700">{error}</p>{/if}
                {#if rows.length == 0}
                    <p class="text-gray-600" data-testid="resources-none">Nothing downloaded{loading ? ' (checking…)' : '.'}</p>
                {:else}
                    <table class="w-full" data-testid="resources-rows">
                        <tbody>
                            {#each rows as r (r.id)}
                                <tr class="border-t border-gray-200 align-top" data-testid={`resources-row-${r.id}`}>
                                    <td class="py-1 pr-2">
                                        <div>
                                            {r.label}
                                            <span class="text-xs text-gray-500">{#if r.downloaded}· {r.files.length} file{r.files.length == 1 ? '' : 's'}{:else}· not downloaded{/if}{#if r.in_use}{' · '}in use{/if}</span>
                                        </div>
                                        {#if r.description}<div class="text-xs text-gray-500">{r.description}</div>{/if}
                                        {#if progress[r.id]}
                                            <div class="text-xs" data-testid={`resources-status-${r.id}`}>
                                                {#if progress[r.id].error}<span class="text-red-700">{progress[r.id].error}</span>
                                                {:else if progress[r.id].done}<span class="text-green-700">Ready.</span>
                                                {:else}Downloading…{#if progress[r.id].pct != null}{' '}{progress[r.id].pct}%{/if}
                                                {/if}
                                            </div>
                                        {/if}
                                    </td>
                                    <td class="py-1 pr-2 text-right tabular-nums whitespace-nowrap">{r.downloaded ? format_bytes(r.size) : ''}</td>
                                    <td class="py-1 text-right whitespace-nowrap space-x-1">
                                        {#if r.can_download}
                                            <button type="button" class={cbtn} onclick={() => download(r)} disabled={busy(r)}
                                                    data-testid={`resources-download-${r.id}`}>{r.downloaded ? 'Load' : 'Download'}</button>
                                        {/if}
                                        {#if r.downloaded}
                                            <button type="button" class={dbtn} onclick={() => remove(r)} disabled={busy(r)}
                                                    data-testid={`resources-delete-${r.id}`}>Delete</button>
                                        {/if}
                                    </td>
                                </tr>
                            {/each}
                        </tbody>
                    </table>
                    <p class="mt-1 text-xs text-gray-500">Deleted files are downloaded again the next time they're needed.</p>
                {/if}
            </section>

            <section>
                <h3 class="font-semibold text-gray-900 mb-1">Preview segments</h3>
                {#if kept_previews.length == 0}
                    <p class="text-gray-600" data-testid="resources-no-previews">None kept.</p>
                {:else}
                    <p class="text-gray-600 mb-1">Layers shown under the waveform and never saved as annotations, kept per kit.</p>
                    <ul class="space-y-1" data-testid="resources-previews">
                        {#each kept_previews as k (k.kit)}
                            <li class="flex items-center justify-between">
                                <span>Kit <span class="font-mono">{k.kit}</span>{#if k.kit == span_layers.kit}{' '}(this one){/if}: {k.layers} layer{k.layers == 1 ? '' : 's'}, {k.spans} span{k.spans == 1 ? '' : 's'}</span>
                                <button type="button" class={btn} onclick={() => forget_previews(k.kit)} data-testid={`resources-clear-previews-${k.kit}`}>Clear</button>
                            </li>
                        {/each}
                    </ul>
                {/if}
            </section>

            <section>
                <h3 class="font-semibold text-gray-900 mb-1">Local audio files</h3>
                {#if handles.length == 0}
                    <p class="text-gray-600" data-testid="resources-no-handles">None remembered.</p>
                {:else}
                    <p class="text-gray-600 mb-1">
                        Kits whose audio file this browser reopens without asking.
                        Forgetting one only means choosing the file again; the file
                        itself is untouched.
                    </p>
                    <ul class="space-y-1" data-testid="resources-handles">
                        {#each handles as h (h.uid)}
                            <li class="flex items-center justify-between">
                                <span><span class="font-mono">{h.name}</span> <span class="text-xs text-gray-500">· kit {h.uid}</span></span>
                                <button type="button" class={btn} onclick={() => forget_handle(h.uid)}>Forget</button>
                            </li>
                        {/each}
                    </ul>
                    <button type="button" class="{dbtn} mt-2" onclick={forget_all_handles} data-testid="resources-forget-handles">Forget all</button>
                {/if}
            </section>

            <section>
                <h3 class="font-semibold text-gray-900 mb-1">Settings kept in this browser</h3>
                <ul class="space-y-1">
                    {#each settings as s (s.key)}
                        <li class="flex items-center justify-between">
                            <span>{s.label}: <span class="font-mono text-xs text-gray-600">{s.value ?? 'not set'}</span></span>
                            {#if s.value != null}
                                <button type="button" class={btn} onclick={() => reset(s.key)} data-testid={`resources-reset-${s.key}`}>Reset</button>
                            {/if}
                        </li>
                    {/each}
                </ul>
            </section>
        </div>
    {/snippet}
</BaseDialog>
