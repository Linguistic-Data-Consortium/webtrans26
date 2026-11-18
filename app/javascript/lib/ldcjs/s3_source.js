// Turning a kit's s3:// source into a bucket and a key — the one place that
// does it.
//
// There used to be five: s3url() in aws_helper.js, a byte-identical copy of it
// in aws.js, and a four-line block pasted into init.js twice and
// waveform/helpers.js once that took the bucket from the manifest's value for a
// source and the key from the source's own name. Those agreed only because the
// manifest maps every source to itself. aws/s3_project_prefixes.md traces why
// that mattered: the per-project rewrite below changes what a source means, and
// it had to land everywhere at once or not at all.
//
// Two rules, chosen by whether the server sent a project context
// (window.ldc_work_work.s3_project, set by set_s3_project):
//
//   off  s3://bucket/key        → bucket, key          — exactly s3url(), as before
//   on   s3://anything/at/all   → <the one bucket>, <project_id>/anything/at/all
//
// With the rule on, nothing after s3:// is a bucket name: there is one bucket,
// and a source names a path under its project's prefix. So s3://foo is valid
// (key "<id>/foo"), where s3url() returns {} for it because it wants a slash.
//
// The rewrite is a convenience, not a security boundary. What stops a user
// reading another project's prefix is the session policy the server builds for
// POST /s3_session; this only makes every request land where that policy
// already allows.
import { s3url, getSignedUrlPromise, headObject } from './aws_helper';
import { signed_url as session_signed_url, head_object as session_head_object } from './s3_session';

let project = null;

// { bucket, project_id } from the server, or nothing to leave the rule off.
// project_id may be null — a kit whose task has no project — and then no s3://
// source resolves at all, rather than resolving to the bucket root.
function set_s3_project(p){
  project = (p && p.bucket) ? { bucket: p.bucket, project_id: p.project_id ?? null } : null;
}

function s3_project(){ return project; }

const PROJECT_RULE = /^s3:\/\/(.+)/;

// Pure: a source string to { bucket, key }, or {} when it isn't one this rule
// can resolve. ctx defaults to the page's project context; tests pass their own.
function resolve_s3_source(src, ctx = project){
  if(typeof src !== 'string') return {};
  if(!ctx) return s3url(src);
  const m = src.match(PROJECT_RULE);
  const id = Number(ctx.project_id);
  if(!m || ctx.project_id == null || !Number.isInteger(id)) return {};
  return { bucket: ctx.bucket, key: `${id}/${m[1]}` };
}

// Which string to resolve for manifest entry k: the entry's own name if it is
// an s3 source, else the manifest's value for it if that is. Both are looked at,
// in this order, at every site — before, some sites read one and some the other,
// and only the manifest's identity mapping hid the difference.
function entry_source(k, urls, ctx = project){
  if(resolve_s3_source(k, ctx).bucket) return k;
  const v = urls && urls[k];
  if(typeof v === 'string' && resolve_s3_source(v, ctx).bucket) return v;
  return null;
}

function not_resolvable(src){
  return Promise.reject(new Error(`not an s3 source this page can resolve: ${src}`));
}

// A presigned GET for src, from whichever mechanism the rule belongs to: the
// per-project session when it is on, the Cognito path (aws_helper.js) when off.
function signed_url_for(src, ctx = project){
  const r = resolve_s3_source(src, ctx);
  if(!r.bucket) return not_resolvable(src);
  return ctx ? session_signed_url(r.bucket, r.key) : getSignedUrlPromise(r.bucket, r.key);
}

function head_source(src, ctx = project){
  const r = resolve_s3_source(src, ctx);
  if(!r.bucket) return not_resolvable(src);
  return ctx ? session_head_object(r.bucket, r.key) : headObject(r.bucket, r.key);
}

// Sign src and record the URL as urls[k] — what the per-file
// signed_url_for_audio helpers did.
function sign_into(urls, k, src, ctx = project){
  return signed_url_for(src, ctx).then((url) => {
    urls[k] = url;
    return { wav: k, wav_url: url };
  });
}

// Manifest entry k to something playable: { wav: k, wav_url }.
//
//   an s3 source (k itself or urls[k]) → signed
//   an http url                        → used as it stands
//   anything else in urls[k]           → used as it stands
//   an s3-looking value that won't resolve → alert, undefined
//   nothing in urls[k]                 → undefined
//
// The last two return undefined because that is what every copy this replaces
// returned, and callers test for it.
function resolve_audio(k, urls, ctx = project){
  if(/^http/.test(k)) urls[k] = k;
  const src = entry_source(k, urls, ctx);
  if(src) return sign_into(urls, k, src, ctx);
  if(!urls[k]) return undefined;
  if(String(urls[k]).startsWith('s3')){
    alert(`can't find the audio for ${k} — the kit's source should be an s3:// url, an http url, or a path`);
    return undefined;
  }
  return Promise.resolve({ wav: k, wav_url: urls[k] });
}

export {
  set_s3_project,
  s3_project,
  resolve_s3_source,
  entry_source,
  signed_url_for,
  head_source,
  sign_into,
  resolve_audio
};
