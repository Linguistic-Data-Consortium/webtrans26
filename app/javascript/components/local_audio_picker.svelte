<script>
    // Asks for the audio file of a local_audio kit, before the work page loads
    // anything. Two cases:
    //
    //   local_audio_url   no kit yet. The file's name and size go to the
    //                     server, which makes and assigns the OnTheFly kit and
    //                     replies with the work page's data for it.
    //   expected_name     the kit exists (a reload, or coming back to it), and
    //                     this is its file again — checked against the name and
    //                     size it was made with, since the transcript is timed
    //                     against that recording.
    //
    // Where the browser can keep a handle to the file (local_audio_handles.js)
    // it's chosen through showOpenFilePicker, and `saved` is what a returning
    // kit's handle could do: { handle, ask: true } offers a one-click reopen,
    // { error } says why it couldn't be reused. Either way the file itself
    // stays here; onready gets the File, and the handle when there is one.
    import { local_file_mismatch, read_local_range } from '../lib/ldcjs/local_audio';
    import { can_keep_handles, read_handle } from '../lib/ldcjs/local_audio_handles';

    let { local_audio_url = null, expected_name = null, expected_size = null,
          saved = null, store = null, kit_uid = null, onready } = $props();

    let error = $state(saved?.error || null);
    let busy = $state(false);
    const keep_handles = can_keep_handles();

    // The waveform reads a WAV header and nothing else, so anything else is
    // turned away here rather than after a kit has been made for it.
    async function is_wav(file){
        if(file.size < 12) return false;
        const b = new Uint8Array(await read_local_range(file, 0, 11));
        const tag = (i) => String.fromCharCode(b[i], b[i + 1], b[i + 2], b[i + 3]);
        return tag(0) === 'RIFF' && tag(8) === 'WAVE';
    }

    async function use(file, handle){
        if(!(await is_wav(file))){
            error = `${file.name} isn't a WAV file. Only WAV audio can be opened.`;
            return;
        }
        if(expected_name){
            const mismatch = local_file_mismatch(file, expected_name, expected_size);
            if(mismatch){
                error = mismatch;
                return;
            }
            onready(file, null, handle);
            return;
        }
        const r = await fetch(local_audio_url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
            },
            credentials: 'same-origin',
            body: JSON.stringify({ name: file.name, size: file.size })
        });
        const body = await r.json().catch(() => ({}));
        if(body.reload){
            window.location.reload();
            return;
        }
        if(!r.ok){
            error = body.error || `The server refused (${r.status}).`;
            return;
        }
        onready(file, body, handle);
    }

    async function attempt(f){
        error = null;
        busy = true;
        try {
            await f();
        }
        catch(err){
            if(err?.name === 'AbortError') return; // closed the file dialog
            error = `Couldn't open the file: ${err?.message || err}`;
        }
        finally {
            busy = false;
        }
    }

    function chose(e){
        const input = e.currentTarget;
        const file = input.files[0];
        if(!file) return;
        attempt(() => use(file)).then(() => input.value = '');
    }

    function choose_with_handle(){
        attempt(async () => {
            const [ handle ] = await window.showOpenFilePicker({
                multiple: false,
                types: [ { description: 'WAV audio', accept: { 'audio/wav': [ '.wav' ] } } ]
            });
            await use(await handle.getFile(), handle);
        });
    }

    // The click is what lets the browser re-grant access without a dialog.
    function reopen(){
        attempt(async () => {
            const p = await saved.handle.requestPermission({ mode: 'read' });
            if(p !== 'granted'){
                error = `Permission to read ${expected_name} wasn't given. Choose the file instead.`;
                return;
            }
            const r = await read_handle(store, kit_uid, saved.handle, expected_name, expected_size);
            if(r.error){
                error = r.error;
                saved = null;
                return;
            }
            onready(r.file, null, r.handle);
        });
    }
</script>

<div class="max-w-xl mx-auto mt-16 p-6 bg-white border border-gray-200 rounded-lg shadow-sm">
    <h2 class="text-lg font-semibold text-gray-900">
        {expected_name ? 'Open this kit’s audio again' : 'Choose an audio file'}
    </h2>
    {#if expected_name}
        <p class="mt-2 text-sm text-gray-700">
            This kit's audio is a file on your computer:
            <span class="font-mono break-all">{expected_name}</span>.
            {#if saved?.ask}
                Allow this page to read it again to carry on.
            {:else}
                Choose it again to carry on.
            {/if}
        </p>
    {:else}
        <p class="mt-2 text-sm text-gray-700">
            This task transcribes audio from your own computer. Choose a WAV file
            and a new kit will be made for it.
        </p>
    {/if}
    <p class="mt-2 text-sm text-gray-500">
        The audio stays on your computer. Only its file name and size are sent,
        along with your transcript. SAD and ASR are unavailable.
    </p>
    <div class="mt-4 flex flex-wrap items-center gap-3">
        {#if saved?.ask}
            <button type="button" onclick={reopen} disabled={busy} data-testid="local-audio-reopen"
                    class="py-2 px-4 rounded bg-blue-600 text-white text-sm hover:bg-blue-700 disabled:opacity-50">
                Open {expected_name}
            </button>
        {/if}
        {#if keep_handles}
            <button type="button" onclick={choose_with_handle} disabled={busy} data-testid="local-audio-choose"
                    class="py-2 px-4 rounded text-sm disabled:opacity-50 {saved?.ask ? 'border border-gray-300 text-gray-700 hover:bg-gray-50' : 'bg-blue-600 text-white hover:bg-blue-700'}">
                {saved?.ask ? 'Choose a different file…' : 'Choose audio file…'}
            </button>
        {:else}
            <label class="inline-block">
                <span class="sr-only">Audio file</span>
                <input type="file" accept=".wav,audio/wav,audio/x-wav" onchange={chose} disabled={busy}
                       data-testid="local-audio-input"
                       class="block text-sm text-gray-700 file:mr-3 file:py-2 file:px-4 file:rounded file:border-0 file:bg-blue-600 file:text-white hover:file:bg-blue-700" />
            </label>
        {/if}
    </div>
    {#if busy}
        <p class="mt-3 text-sm text-gray-600">Opening…</p>
    {/if}
    {#if error}
        <p class="mt-3 text-sm text-red-700" role="alert">{error}</p>
    {/if}
</div>
