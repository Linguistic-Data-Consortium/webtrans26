// The session ended while the editor was open — saves wait until it works again.
//
// A save the server refuses with a 401 never touched the log: authentication
// comes before anything reads the messages. So nothing is lost by holding that
// batch, and everything queued behind it, and sending them unchanged once the
// user has signed in again — the log ends up exactly as it would have. That's
// what this does (modification2.js save_failed), instead of what it used to:
// the rejected save left the save queue rejected, every later save was skipped
// without a word, and the transcript went on showing edits that weren't being
// recorded until the next reload threw them away.
//
// Signing in happens in another tab (session_banner.svelte opens it), because
// navigating this one would lose the edits it's holding. The two share the
// session cookie, so once that tab is signed in, a request from this one
// works. This checks every POLL_MS, and when told to (the banner's button).
import { getp_no_catch } from '../getp';

const POLL_MS = 5000;

const session_hold = $state({ held: false });

let hold = null;     // the promise everything waiting for the session waits on
let release = null;  // resolves it
let timer = null;

// Resolves once a request works again. Calls during the same hold share it.
function hold_until_signed_in(){
    if(!hold){
        session_hold.held = true;
        hold = new Promise((resolve) => { release = resolve; });
        timer = setInterval(try_resume, POLL_MS);
    }
    return hold;
}

// Is the session usable? Any signed-in JSON request answers; /echo is the
// cheapest. Still refused (401), or blocked by an expired password or MFA
// setup (403): keep holding — those are finished in the other tab.
async function try_resume(){
    if(!hold) return true;
    const ok = await getp_no_catch('/echo').then(() => true, () => false);
    if(ok && hold){
        clearInterval(timer);
        timer = null;
        session_hold.held = false;
        const go = release;
        hold = null;
        release = null;
        go();
    }
    return ok;
}

// For tests.
function session_hold_reset(){
    clearInterval(timer);
    timer = null;
    hold = null;
    release = null;
    session_hold.held = false;
}

export { session_hold, hold_until_signed_in, try_resume, session_hold_reset };
