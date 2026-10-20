// The page and the server have stopped agreeing — say so, and say what to do.
//
// Every write goes out optimistically: the client applies the change to its own
// graph rows, renders, and only then posts the message (see modification2.js and
// ARCHITECTURE.md, "Editing runs in one direction"). That is what makes typing
// feel immediate, and it means the client's state is a *prediction* of what the
// log will hold. The server's reply carries its own replay of the log, so the
// two can be compared — and when they differ, the prediction lost and this page
// is showing something that isn't recorded.
//
// There is no safe automatic recovery. The annotation log is the record and the
// client cannot rewrite it, so the only way back into step is to reload and let
// the tool rebuild from /kits/get. Hence: tell the annotator, keep telling them,
// and offer the reload.
//
// Before this existed, the three ways to get here were all effectively silent:
//
//   a value mismatch        console.error('avm error 6') and nothing else
//   an 'add' mismatch       called error_in_message(), which was never defined,
//                           so it threw TypeError instead of reporting
//   a locked tree           added a class to #tree_locked_modal, an element no
//                           view has rendered since the Svelte rewrite
//
// So an annotator could keep typing into a page whose writes were being refused,
// and find out when they next reloaded. That is the thing this fixes.
const desync = $state({
    // Null until something goes wrong; after that it stays set. Deliberately
    // not dismissible — the page really is wrong, and hiding the notice would
    // only hide that.
    reason: null,
    // The technical detail, for the console and a bug report. Not shown to the
    // annotator, who can't act on 'avm error 6'.
    detail: null
});

// `reason` should be a short phrase an annotator can act on. The first call
// wins: a divergence usually produces several failing messages in a row, and
// the first is the one closest to the cause.
function report_desync(reason, detail = null){
    if(desync.reason) return;
    desync.reason = reason;
    desync.detail = detail;
    console.error(`[desync] ${reason}`, detail ?? '');
}

function desynced(){
    return !!desync.reason;
}

// For tests, and for a reload that hasn't happened yet.
function desync_clear(){
    desync.reason = null;
    desync.detail = null;
}

export { desync, report_desync, desynced, desync_clear };
