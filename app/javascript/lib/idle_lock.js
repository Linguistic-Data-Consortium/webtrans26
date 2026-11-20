// The screen lock: after a stretch with no keyboard, mouse or touch input, sign
// out and replace the page with the sign-in form, so nothing of the user's work
// stays on screen. The limit is the session timeout (SESSION_IDLE_MINUTES,
// default 30), rendered into the page as <meta name="idle-lock-seconds">, so
// the screen and the server session end together.
//
// Activity is shared between this site's tabs through localStorage. A tab left
// in the background mustn't lock while another is in use: they share one
// session, and the lock signs it out.
//
// Before clearing, focus leaves whatever field had it (the editor saves a line
// when its field loses focus), the page is hidden, and the lock waits a few
// seconds for the editor's saves to finish (window.ldc_saves_settled, from
// modification2.js). After the sign-out, the page is replaced rather than
// navigated from, so Back doesn't return to it. Signed-in pages are also sent
// with Cache-Control: no-store, and a page restored from the back-forward cache
// checks again at once.
const KEY = 'idle-lock-last-activity';
const EVENTS = [ 'keydown', 'pointerdown', 'mousedown', 'wheel', 'touchstart', 'scroll', 'mousemove' ];
const NOTE_EVERY_MS = 2000;      // activity is written at most this often
const SAVE_WAIT_MS = 5000;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function clear_screen(){
    try { document.activeElement?.blur?.(); } catch(_) {}
    document.documentElement.style.visibility = 'hidden';
    if(typeof window.ldc_saves_settled === 'function'){
        await Promise.race([ window.ldc_saves_settled(), sleep(SAVE_WAIT_MS) ]);
    }
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    try {
        await fetch('/session?idle=1', {
            method: 'DELETE', credentials: 'same-origin', redirect: 'manual',
            headers: { 'X-CSRF-Token': token || '', 'Accept': 'application/json' }
        });
    } catch(_) {}
    window.location.replace('/session/new?idle=1');
}

// Start watching. Returns { check, stop }, or null when there's nothing to do
// (a signed-out page has no limit).
function start_idle_lock({ seconds, lock = clear_screen, now = () => Date.now(),
                           storage = (() => { try { return window.localStorage; } catch(_) { return null; } })(),
                           check_every_ms = 15000 } = {}){
    if(!seconds || !(seconds > 0)) return null;
    const limit = seconds * 1000;
    let last_here = 0;
    let locked = false;

    const shared = () => { try { return Number(storage?.getItem(KEY)) || 0; } catch(_) { return 0; } };
    const note = () => {
        const t = now();
        if(t - last_here < NOTE_EVERY_MS) return;
        last_here = t;
        try { storage?.setItem(KEY, String(t)); } catch(_) {}
    };
    const check = () => {
        if(locked) return true;
        if(now() - Math.max(last_here, shared()) >= limit){
            locked = true;
            lock();
        }
        return locked;
    };

    note(); // loading the page is activity
    EVENTS.forEach((e) => window.addEventListener(e, note, { capture: true, passive: true }));
    const timer = setInterval(check, check_every_ms);
    // A sleeping laptop or a hidden tab doesn't run timers on time: check the
    // moment it's looked at again.
    document.addEventListener('visibilitychange', check);
    window.addEventListener('focus', check);
    window.addEventListener('pageshow', check);

    return {
        check,
        stop(){
            clearInterval(timer);
            EVENTS.forEach((e) => window.removeEventListener(e, note, { capture: true }));
            document.removeEventListener('visibilitychange', check);
            window.removeEventListener('focus', check);
            window.removeEventListener('pageshow', check);
        }
    };
}

function start_idle_lock_from_page(){
    const seconds = Number(document.querySelector('meta[name="idle-lock-seconds"]')?.content);
    return start_idle_lock({ seconds });
}

export { start_idle_lock, start_idle_lock_from_page, clear_screen, KEY };
