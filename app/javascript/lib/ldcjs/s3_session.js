// Per-project S3 credentials: the client half of POST /s3_session.
//
// The parallel path to aws_helper.js, described in aws/s3_project_prefixes.md.
// There, the browser exchanges a Cognito token for credentials, so everyone
// gets the identity pool's one role. Here the server does the exchange, with a
// session policy built from the caller's project memberships, and hands back
// plain temporary credentials. This module only holds them.
//
// Held in memory and nowhere else. Not localStorage: that would outlive the
// credentials' own lifetime and hand them to anything else on the origin. When
// they are close to expiry the next caller fetches new ones.
//
// Fetched on demand, never at import time — for the reason aws_helper.js gives:
// a page that imports this and never touches S3 should not ask the server for
// anything, and on an instance with the mechanism off that request would fail
// and log on every load.
import { S3Client, GetObjectCommand, HeadObjectCommand, ListObjectsV2Command, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { s3_session_available } from './service_config';

// Re-fetch this long before the server's stated expiry, so a request signed
// just before it does not arrive just after.
const MARGIN_MS = 60 * 1000;

let session = null;   // { credentials, region, bucket, expires_ms }
let inflight = null;  // the one fetch in progress, shared by concurrent callers
let s3 = null;

function csrf_headers(){
  const meta = typeof document !== 'undefined' && document.querySelector('meta[name="csrf-token"]');
  return meta ? { 'X-CSRF-Token': meta.content } : {};
}

function fresh(){
  return session && session.expires_ms - MARGIN_MS > Date.now();
}

// The current session, fetching one if there is none or it is about to lapse.
// Rejects with the server's own message — "You are not a member of any
// project", say — rather than resolving to undefined, which is how the old path
// used to fail: as a TypeError somewhere far from the cause.
function get_session(){
  if(!s3_session_available()){
    return Promise.reject(new Error('Per-project S3 is not configured on this server'));
  }
  if(fresh()) return Promise.resolve(session);
  if(inflight) return inflight;
  inflight = fetch('/s3_session', {
    method: 'POST',
    headers: { 'Accept': 'application/json', ...csrf_headers() },
    credentials: 'same-origin'
  })
  .then(async (res) => {
    const body = await res.json().catch(() => ({}));
    if(!res.ok) throw new Error(body.error || `POST /s3_session answered ${res.status}`);
    return body;
  })
  .then((b) => {
    session = {
      credentials: {
        accessKeyId: b.credentials.access_key_id,
        secretAccessKey: b.credentials.secret_access_key,
        sessionToken: b.credentials.session_token,
        expiration: new Date(b.expires_at)
      },
      region: b.region,
      bucket: b.bucket,
      expires_ms: Date.parse(b.expires_at)
    };
    return session;
  })
  .finally(() => { inflight = null; });
  return inflight;
}

// One S3 client for the page. Its credentials are a provider rather than a
// value, so the SDK asks again on each request and an expired session is
// replaced without rebuilding the client.
function client(){
  if(s3) return Promise.resolve(s3);
  return get_session().then((s) => {
    if(!s3) s3 = new S3Client({ region: s.region, credentials: () => get_session().then((x) => x.credentials) });
    return s3;
  });
}

// A presigned URL lives no longer than the credentials that signed it, however
// long expiresIn says.
function signed_url(Bucket, Key, expiresIn = 3600){
  return client().then((c) => getSignedUrl(c, new GetObjectCommand({ Bucket, Key }), { expiresIn }));
}

function head_object(Bucket, Key){
  return client().then((c) => c.send(new HeadObjectCommand({ Bucket, Key })));
}

// The session policy allows listing only under the caller's own project
// prefixes, so a listing without a Prefix — the bucket root — is refused.
function list_objects(params){
  return client().then((c) => c.send(new ListObjectsV2Command(params)));
}

function put_object(Bucket, Key, Body, ContentType){
  return client().then((c) => c.send(new PutObjectCommand({ Bucket, Key, Body, ContentType })));
}

// For tests: forget the session and the client.
function _reset(){
  session = null;
  inflight = null;
  s3 = null;
}

export { get_session, client, signed_url, head_object, list_objects, put_object, _reset };
