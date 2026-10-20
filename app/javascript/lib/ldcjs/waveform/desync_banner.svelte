<script>
    // Shown when the page and the server have stopped agreeing — see
    // desync.svelte.js for how that is detected and why reloading is the only
    // way back.
    //
    // Fixed to the top and not dismissible. The annotator may be mid-sentence
    // and the waveform is scrolled somewhere; a dialog that steals focus would
    // lose both, and a toast that fades would let them keep typing into a page
    // whose writes aren't landing. So: persistent, out of the way, and clear
    // about what to do.
    //
    // Not an alert(): a modal dialog blocks every subsequent browser event,
    // which would also freeze the scripted harnesses in script/.
    import { desync } from './desync.svelte';

    function reload(){
        window.location.reload();
    }
</script>

{#if desync.reason}
    <div
        class="fixed top-0 left-0 right-0 z-[9999] bg-red-700 text-white px-4 py-2 flex items-center gap-4 shadow-lg"
        role="alert"
        aria-live="assertive"
    >
        <div class="flex-1 text-sm">
            <strong>This page is out of step with the server.</strong>
            {desync.reason}
            Reload to see what was actually saved — anything typed since will
            need doing again.
        </div>
        <button
            class="shrink-0 bg-white text-red-800 font-semibold text-sm px-3 py-1 rounded hover:bg-red-50"
            onclick={reload}
        >
            Reload
        </button>
    </div>
{/if}
