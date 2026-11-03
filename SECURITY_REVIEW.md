# Open security review items

Things a security review found that need a decision before they can be fixed.
Each says where it stands, why it is open, and what deciding it involves.
Remove an entry once it's resolved.

This file is at the top level, not in `docs/`, on purpose: everything in
`docs/` is listed on the app's documentation pages for every signed-in user.

## 1. CSP: `connect-src` and `media-src` allow any `https:` host

**Where:** `config/initializers/secure_headers.rb`

    connect_src: 'self' wss: https: *.amazonaws.com    (+ ws: http: in development)
    media_src:   'self' https: https://*.amazonaws.com blob: data:

**Why it matters.** `script-src` no longer allows inline script, so injected
script shouldn't run in the first place. If some ever did, though,
`connect-src https:` lets it send whatever the page can read to any server.
A narrow `connect-src` is what would still stop that.

**Why it's open.** A kit's source can be a plain `http(s)` URL on any host, and
the browser fetches it directly, both as `<audio>` (`media-src`) and with
`fetch` for waveform byte ranges (`connect-src`, in `getp_wav`). Narrowing
either list stops audio from loading from any host that isn't on it. Where
audio comes from in practice hasn't been decided.

**What deciding it involves.**

- Always needed: `'self'`, the S3 and Cognito endpoints (`*.amazonaws.com`;
  narrower if the region and buckets are fixed), and `HLT_ENDPOINT`'s origin
  when that is set.
- Then either audio is S3 only (drop `https:` from both lists), or it comes from
  a known set of hosts (read them from configuration, say an `AUDIO_HOSTS`
  variable, and add those), or annotators must be able to load arbitrary
  URLs (keep `https:`, and say so in the comment beside it).
- `wss:` is broader than anything uses now that Action Cable is gone. With
  no WebSocket left it can probably go entirely, apart from Vite's HMR in
  development.
- Checking it: `ApplicationSystemTestCase` fails any system test whose page
  logs a CSP violation, so a narrowed policy that breaks a page tested there
  will show. Audio from an external host isn't covered by the suite; check
  one by hand.

## 2. S3 access through Cognito isn't limited by the app's permissions

**Where:** `POST /token` (`CognitoTokenController`, `get_credentials_from_cognito`
in `app/controllers/concerns/authentication.rb`), used by
`app/javascript/lib/ldcjs/aws_helper.js`.

**The state.** Every signed-in user gets temporary AWS credentials for the same
Cognito "authenticated" role, keyed on their bare user id. The browser uses them
to sign GET URLs for `s3://` kit audio, to list buckets, to write SAD/ASR job
files into `PROMISE_BUCKET` and read the results back, and for a Transcribe
client. The credentials can be copied out of the browser and used directly. So
what an annotator can do in S3 is whatever that role allows, for any key: the
app's kit-level checks never come into it. The repository ships no IAM policy
for the role, and no guidance.

Two smaller points:

- Two instances sharing a pool and provider name (staging and production, say)
  map their user N to the same Cognito identity.
- Credentials last 15 minutes and are renewed by calling `/token` again.

**Options, in increasing effort.**

1. Ship a least-privilege role policy (in `aws/`, explained in
   `docs/DEPLOYMENT.md`):
   - read the audio bucket or prefix only;
   - list only where the bucket browser needs it;
   - write and read in the promise bucket only under
     `${cognito-identity.amazonaws.com:sub}/`, which means changing
     `aws.js` to write job files there;
   - no delete, and no Transcribe unless it's used.

   This caps the damage, but every user can still read every project's audio.
2. Namespace the developer identity, `"#{instance}:#{user.id}"`, so instances
   never share one. Existing identities are replaced by new ones.
3. Presign on the server instead of vending credentials: check kit access, then
   return a short-lived URL for that one object (and presigned PUTs for job
   files). S3 access then follows the app's permissions, at the cost of
   reworking `aws_helper.js` and its callers.
