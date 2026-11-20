<script>
    // Shown while saves are held because the session ended (session_hold.svelte.js).
    // Not the red desync banner: nothing is wrong yet and nothing is lost, as long
    // as this page isn't reloaded or closed. So it says that, and how to carry on.
    //
    // Signing in opens a new tab, which needs a click (a popup opened any other
    // way is blocked), and this tab stays put with the edits it's holding.
    import { session_hold, try_resume } from './session_hold.svelte';

    let checking = $state(false);
    let still_out = $state(false);

    function sign_in(){
        window.open('/session/new', '_blank');
    }

    async function resume(){
        checking = true;
        still_out = !(await try_resume());
        checking = false;
    }
</script>

{#if session_hold.held}
    <div
        class="fixed top-0 left-0 right-0 z-[9998] bg-amber-500 text-black px-4 py-2 flex items-center gap-4 shadow-lg"
        role="alert"
        aria-live="assertive"
        id="session-hold-banner"
    >
        <div class="flex-1 text-sm">
            <strong>You've been signed out, so your latest changes aren't saved yet.</strong>
            They're kept on this page — don't reload or close it. Sign in again in the
            tab that opens, then come back here: saving carries on by itself.
            {#if still_out}<em>Not signed in yet.</em>{/if}
        </div>
        <button
            class="shrink-0 bg-white text-amber-900 font-semibold text-sm px-3 py-1 rounded hover:bg-amber-50"
            onclick={sign_in}
        >
            Sign in again
        </button>
        <button
            class="shrink-0 bg-white text-amber-900 font-semibold text-sm px-3 py-1 rounded hover:bg-amber-50 disabled:opacity-60"
            onclick={resume}
            disabled={checking}
        >
            {checking ? 'Checking…' : "I've signed in"}
        </button>
    </div>
{/if}
