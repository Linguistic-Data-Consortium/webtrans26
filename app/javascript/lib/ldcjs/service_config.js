// Where the speech-activity-detection / ASR promise service lives, and which
// S3 bucket it exchanges work through.
//
// Both were string literals repeated across the client — the endpoint in
// waveform/helpers.js and aws.js, the bucket about thirty times in aws.js plus
// a button in components/buckets.svelte — so an instance deployed outside LDC
// had no way to point them anywhere else, and would fail confusingly against
// buckets it could not read.
//
// The server puts them in meta tags (see config/application.rb and
// layouts/application.html.haml); this reads them once, the same way getp.js
// reads the CSRF token.
//
// Both default to empty. This app is the public release, so an instance that
// has configured nothing must not fall back to LDC's own service — speech
// activity detection and ASR are unavailable until the server sets them.
const DEFAULT_ENDPOINT = '';
const DEFAULT_BUCKET   = '';

function meta(name, fallback){
    if(typeof document === 'undefined') return fallback;
    const el = document.querySelector(`meta[name="${name}"]`);
    const v = el && el.content;
    return (v && v.length) ? v : fallback;
}

// Read lazily rather than at import time: these modules are imported by tests
// and by code that runs before the document is parsed, and a value captured
// then would be the fallback for the rest of the session.
export function hlt_endpoint(){ return meta('hlt-endpoint', DEFAULT_ENDPOINT); }
export function promise_bucket(){ return meta('promise-bucket', DEFAULT_BUCKET); }

// Whether this instance has anywhere to send the work. Both halves are needed:
// the endpoint receives the request, the bucket carries the audio in and the
// result back. Callers use this to stay out of the way rather than to fail —
// speech activity detection and ASR are optional, and an instance that has not
// configured them should say so, not raise.
export function services_configured(){
    return Boolean(hlt_endpoint() && promise_bucket());
}

// Whether the browser can reach S3 at all. The layout renders this from the
// server's own check — Cognito credentials plus a region — because the browser
// gets S3 credentials only from POST /token and has no other route.
//
// Defaults to false when the tag is absent, which is the safe direction: an
// unconfigured instance stays out of the way instead of calling /token and
// failing somewhere the user cannot interpret.
export function s3_configured(){
    return meta('s3-available', 'false') === 'true';
}

export default { hlt_endpoint, promise_bucket, services_configured, s3_configured };
