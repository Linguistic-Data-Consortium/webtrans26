<script>
    let {
        dialogRef = $bindable(),
        size = "sm:max-w-4xl",
        title = null,
        showClose = true,
        onKeydown = null,
        onClose = null,
        children
    } = $props();

    let dialog = $state(null);

    $effect(() => {
        if (dialog) {
            dialogRef = dialog;
        }
    });

    function handleClick(e) {
        if (e.target.tagName === 'DIALOG') {
            dialog.close();
            onClose?.();
        }
    }

    function handleKeydown(e) {
        onKeydown?.(e);
    }

    function closeDialog() {
        dialog.close();
        onClose?.();
    }
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<dialog
    bind:this={dialog}
    onclick={handleClick}
    onkeypress={() => null}
    class="{size} p-0 rounded-xl shadow-2xl border border-gray-200 bg-white text-gray-900"
>
    {#if title}
        <div class="px-6 py-4 border-b border-gray-200 bg-gradient-to-r from-indigo-50 via-purple-50 to-pink-50 relative">
            <h3 class="text-lg font-semibold text-gray-900 pr-8">{title}</h3>
            {#if showClose}
                <button
                    onclick={closeDialog}
                    class="absolute right-4 top-4 text-gray-400 hover:text-gray-600 transition-colors p-1 rounded-lg hover:bg-white/50"
                    aria-label="Close dialog"
                >
                    <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                </button>
            {/if}
        </div>
    {/if}
    <div class="dialog-content">
        {@render children({ dialog })}
    </div>
</dialog>

<style>
    dialog {
        max-height: 90vh;
        animation: dialogFadeIn 0.2s ease-out;
        position: fixed !important;
        inset: auto !important;
        top: 50% !important;
        left: 50% !important;
        transform: translate(-50%, -50%) !important;
        margin: 0 !important;
    }

    @keyframes dialogFadeIn {
        from {
            opacity: 0;
            transform: translate(-50%, -50%) scale(0.95) !important;
        }
        to {
            opacity: 1;
            transform: translate(-50%, -50%) scale(1) !important;
        }
    }

    dialog::backdrop {
        backdrop-filter: blur(3px);
        background: rgba(0, 0, 0, 0.5);
        animation: backdropFadeIn 0.2s ease-out;
    }

    @keyframes backdropFadeIn {
        from {
            opacity: 0;
        }
        to {
            opacity: 1;
        }
    }

    .dialog-content {
        max-height: calc(90vh - 4rem);
    }
</style>
