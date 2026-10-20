<script>
    // Vimium-style hint overlay. When activated (default: pressing `f`),
    // every visible actionable element on the page is given a letter hint,
    // shown as a small floating badge. Typing the letter activates the
    // matching element. Escape cancels.
    //
    // To make a non-standard element hintable, set `data-hintable` on it.
    // To skip an otherwise-hintable element, set `data-no-hint`.

    let {
        trigger = 'f',
        // Default selector covers links, buttons, form controls, and anything
        // tagged with `data-hintable`. Things with `data-no-hint` are skipped
        // (filtered after the query).
        //
        // We intentionally do NOT include `[tabindex]:not([tabindex="-1"])` —
        // it scoops up generic focus-management wrappers (e.g. bits-ui's
        // Tabs.Content panel renders with tabindex="0"), and `dedupe_nested`
        // then keeps the wrapper and drops every hintable inside it.
        selector = 'a[href], button:not([disabled]), [role="button"], input[type="submit"], input[type="button"], input[type="checkbox"], input[type="radio"], select, summary, [data-hintable]'
    } = $props();

    let active = $state(false);
    let buffer = $state('');
    let hints = $state([]);

    function generate_labels(n) {
        const A = 'a'.charCodeAt(0);
        const labels = [];
        if (n <= 26) {
            for (let i = 0; i < n; i++) labels.push(String.fromCharCode(A + i));
        } else {
            // 2-char hints: aa, ab, ... zz (676 combos)
            for (let i = 0; i < n; i++) {
                const hi = Math.floor(i / 26);
                const lo = i % 26;
                labels.push(String.fromCharCode(A + hi) + String.fromCharCode(A + lo));
            }
        }
        return labels;
    }

    function is_visible(el) {
        if (el.hasAttribute && el.hasAttribute('data-no-hint')) return false;
        const rect = el.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return false;
        if (rect.bottom < 0 || rect.top > window.innerHeight) return false;
        if (rect.right < 0 || rect.left > window.innerWidth) return false;
        const style = window.getComputedStyle(el);
        if (style.visibility === 'hidden' || style.display === 'none' || style.opacity === '0') return false;
        return true;
    }

    // When a hintable element is nested inside another hintable element
    // (e.g. a Tooltip.Trigger inside a Tabs.Trigger), keep only the outer
    // one — the inner is usually a sub-control of the same logical action.
    function dedupe_nested(els) {
        return els.filter(el => !els.some(other => other !== el && other.contains(el)));
    }

    function collect() {
        const raw = Array.from(document.querySelectorAll(selector)).filter(is_visible);
        const els = dedupe_nested(raw);
        const labels = generate_labels(els.length);
        return els.map((el, i) => {
            const rect = el.getBoundingClientRect();
            return {
                el,
                key: labels[i],
                x: rect.left,
                y: rect.top
            };
        });
    }

    function activate() {
        const fresh = collect();
        if (fresh.length === 0) return;
        hints = fresh;
        buffer = '';
        active = true;
    }
    function deactivate() {
        active = false;
        buffer = '';
        hints = [];
    }

    function activate_hint(h) {
        const el = h.el;
        deactivate();
        // Defer so our own keydown handler unwinds before any focus/click
        // side effects run (which might re-enter and confuse state).
        setTimeout(() => {
            const tag = el.tagName;
            if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || el.isContentEditable) {
                el.focus();
                if (tag === 'INPUT' && (el.type === 'checkbox' || el.type === 'radio')) el.click();
            } else if (typeof el.click === 'function') {
                el.click();
            }
        }, 0);
    }

    function input_focused() {
        const el = document.activeElement;
        if (!el) return false;
        return el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable;
    }

    // Consumed by us — also stops other window listeners from acting on the
    // same key (otherwise typing the hint letter `h` would also open the
    // page cheat sheet, etc).
    function consume(e) {
        e.preventDefault();
        e.stopImmediatePropagation();
    }

    function on_keydown(e) {
        if (e.key === 'Escape') {
            if (active) {
                consume(e);
                deactivate();
            }
            return;
        }
        if (!active) {
            if (e.key === trigger && !e.ctrlKey && !e.metaKey && !e.altKey && !input_focused()) {
                consume(e);
                activate();
            }
            return;
        }
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        if (e.key.length !== 1 || !/[a-z]/i.test(e.key)) {
            // Any non-letter key while active cancels.
            consume(e);
            deactivate();
            return;
        }
        consume(e);
        buffer += e.key.toLowerCase();
        const exact = hints.find(h => h.key === buffer);
        if (exact) { activate_hint(exact); return; }
        const has_prefix = hints.some(h => h.key.startsWith(buffer));
        if (!has_prefix) deactivate();
    }

    $effect(() => {
        window.addEventListener('keydown', on_keydown, true);
        return () => window.removeEventListener('keydown', on_keydown, true);
    });
</script>

{#if active}
    <!-- Fixed overlay anchored to the viewport. Coordinates come from
         getBoundingClientRect() which is also viewport-relative, so they
         match without scroll math. pointer-events-none lets clicks pass
         through; we handle activation via the keyboard. -->
    <div class="fixed inset-0 pointer-events-none" style="z-index: 99999;">
        {#each hints as h}
            <span
                class="absolute inline-block bg-yellow-300 text-black text-[10px] font-bold font-mono leading-none px-1 py-0.5 rounded border border-yellow-700 shadow uppercase {h.key.length > 1 && buffer && h.key.startsWith(buffer) ? 'ring-2 ring-orange-500' : ''}"
                style="left: {h.x}px; top: {h.y}px; transform: translate(-25%, -25%);"
            >{h.key}</span>
        {/each}
    </div>
{/if}
