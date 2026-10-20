<script>
    // Bundled keyboard helpers for any non-waveform page:
    //   f   -> hint-letter overlay (HintOverlay)
    //   h   -> page help cheat sheet
    //   d   -> open /documentation
    //   s   -> sign out (after a confirmation popup)
    //
    // Mount once near the root of the page and you're done. Extra page-
    // specific bindings can be passed via `extraBindings` — they'll show up
    // in the cheat sheet alongside the built-ins.

    import HintOverlay from './hint_overlay.svelte';
    import PageHelpDialog from './page_help_dialog.svelte';
    import BaseDialog from './ldcjs/waveform/dialogs/BaseDialog.svelte';

    let { extraBindings = [] } = $props();

    let help_dialog = $state();
    let signout_dialog = $state();

    function input_focused() {
        const el = document.activeElement;
        if (!el) return false;
        return el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable;
    }

    function go_documentation() {
        window.location.href = '/documentation';
    }
    function confirm_sign_out() {
        signout_dialog?.showModal();
    }
    function do_sign_out() {
        signout_dialog?.close();
        const form = document.querySelector('#newsignout form');
        if (form) form.submit();
    }
    function cancel_sign_out() {
        signout_dialog?.close();
    }
    function signout_dialog_keydown(e) {
        if (e.key === 'y' || e.key === 'Enter') {
            e.preventDefault();
            do_sign_out();
        } else if (e.key === 'n' || e.key === 'Escape') {
            e.preventDefault();
            cancel_sign_out();
        }
    }
    function signout_focus(node) { node.focus(); }

    function on_keydown(e) {
        if (input_focused()) return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        // Skip if another dialog is already open — the dialog's own handler
        // will deal with the key (and avoid us re-opening on top of it).
        if (document.querySelector('dialog[open]')) return;
        switch (e.key) {
            case 'h':
                e.preventDefault();
                help_dialog?.showModal();
                break;
            case 'd':
                e.preventDefault();
                go_documentation();
                break;
            case 's':
                e.preventDefault();
                confirm_sign_out();
                break;
        }
    }

    $effect(() => {
        window.addEventListener('keydown', on_keydown, true);
        return () => window.removeEventListener('keydown', on_keydown, true);
    });
</script>

<HintOverlay />
<PageHelpDialog bind:dialogRef={help_dialog} {extraBindings} />

<BaseDialog bind:dialogRef={signout_dialog} size="sm:max-w-md" title="Sign out?" showClose={false} onKeydown={signout_dialog_keydown}>
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div use:signout_focus tabindex="0" onkeydown={signout_dialog_keydown} class="p-5 outline-none text-sm">
            <p class="text-gray-700 mb-5">Sign out of this session?</p>
            <div class="flex justify-end gap-2">
                <button
                    type="button"
                    onclick={cancel_sign_out}
                    class="inline-flex items-center gap-1 px-3 py-1.5 rounded border border-gray-300 bg-white text-gray-700 text-sm font-medium hover:bg-gray-50"
                >
                    Cancel
                    <kbd class="ml-1 px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px] text-gray-500">n</kbd>
                </button>
                <button
                    type="button"
                    onclick={do_sign_out}
                    class="inline-flex items-center gap-1 px-3 py-1.5 rounded bg-red-600 text-white text-sm font-semibold hover:bg-red-700"
                >
                    Sign out
                    <kbd class="ml-1 px-1.5 py-0.5 bg-red-700/40 border border-red-300/40 rounded font-mono text-[10px] text-white/90">y</kbd>
                </button>
            </div>
        </div>
    {/snippet}
</BaseDialog>
