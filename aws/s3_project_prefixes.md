# Spec: per-project S3 access in `webtrans26`, alongside the current mechanism

| | |
| --- | --- |
| **Source** | **none — new design.** Nothing in this app does per-user S3 scoping, so there is no existing implementation to adapt |
| **Scope** | `webtrans26` |
| **Surveyed** | 2026-11-16 at `59bec6b`; re-checked 2026-11-17 at `7bb928c`, which is the first commit where the `aws/cognito.md` referred to below exists |
| **Status** | spec only — nothing described here is implemented |

Requirements as given: a **parallel** mechanism with the current one left
inactive; best practice as close as possible; a **single bucket**; the mapping
in **Active Record**; prefixes are **project ids**; read access follows project
membership; write access needs membership **plus a higher role, TBD**; and —
because there is only one bucket — a kit source's `s3://…` is **rewritten** to
that bucket plus the project id, so whatever follows `s3://` is a prefix
*under* the project rather than a bucket name.

## The files this refers to

Short names are used throughout; these are the full paths, because one of them
is ambiguous in this repository.

| short name | path |
| --- | --- |
| `aws_helper.js` | `app/javascript/lib/ldcjs/aws_helper.js` |
| `aws.js` | `app/javascript/lib/ldcjs/aws.js` |
| `helpers.js` | `app/javascript/lib/ldcjs/waveform/helpers.js` — **not** `app/javascript/components/helpers.js`, which is a different file |
| `init.js` | `app/javascript/work/init.js` |
| `services.js` | `app/javascript/lib/ldcjs/waveform/services.js` |
| `bucket.svelte`, `promise_bucket.svelte` | `app/javascript/components/` |
| `tasks_controller.rb`, `task_users_controller.rb`, `cognito_token_controller.rb` | `app/controllers/` |
| `s3_session.js`, `S3SessionsController` | **proposed by this spec; they do not exist yet** |

Line numbers are as of the commit in the header and will drift.

## Why the current mechanism cannot be adapted, only replaced

`/token` returns an OpenID token and **the browser exchanges it**:
`aws_helper.js` calls `fromCognitoIdentity`, which hits
`GetCredentialsForIdentity` client-side. The credentials therefore come from
the identity pool's single authenticated role, so every user gets the same
policy. The per-user identity already exists —
`logins: { provider => user_id }` — and buys nothing.

Two consequences that decide the design:

- **Anything the browser passes, the browser chooses.** `fromCognitoIdentity`
  accepts a `customRoleArn`, which makes "return the right role for the user's
  group and let the client pass it" look like the easy answer. It is the one
  shape to avoid: developer-authenticated tokens carry no claims for Cognito's
  role-mapping rules to discriminate on, so if several roles are permitted on
  the pool nothing stops a user asking for another project's.
- **Principal tags cannot express this case.** `GetOpenIdTokenForDeveloperIdentity`
  does accept `PrincipalTags`, and for a single group per user that is the
  neatest answer — one pool, one role, a policy keyed on
  `${aws:PrincipalTag/group}`. But a tag key holds **one value**, and a user
  here belongs to many projects. It would force a "current project" concept
  that the requirement does not have.

So: **the server performs the exchange, and scopes it with a session policy.**

## The mechanism

`POST /s3_session` → the server calls `sts:AssumeRole` against one role, with a
**session policy** built from the caller's project memberships, and returns the
temporary credentials.

```
Aws::STS::Client#assume_role(
  role_arn:          config.x.s3_role_arn,
  role_session_name: "u#{user.id}",       # appears in CloudTrail
  policy:            session_policy_json, # the narrowing
  duration_seconds:  900                  # STS minimum; these go to a browser
)
```

The role's own policy is the **ceiling** — read and write across the whole
bucket. The session policy is the **actual grant**, and the effective
permission is the intersection, so a bug in policy construction fails closed
rather than open. This is the standard shape and the reason not to put
per-project detail in IAM at all: **no AWS object is created or changed when a
project is added or a member joins.** That is what "the mapping lives in Active
Record" buys.

`Aws::STS::Client` ships with `aws-sdk-core`, already a transitive dependency
(`>= 3.264.0`) — **no new gem**. Checked, not assumed.

### The session policy

Two statements, because read and write have different resource sets, and a
third for listing, because `ListBucket` is a **bucket-level** action and
scoping it needs a condition rather than a resource path — the classic trap
here, and the reason a naive policy either denies all listing or exposes the
whole bucket:

```json
{ "Version": "2012-10-17", "Statement": [
  { "Sid": "Read", "Effect": "Allow", "Action": ["s3:GetObject"],
    "Resource": ["arn:aws:s3:::BUCKET/3/*", "arn:aws:s3:::BUCKET/7/*"] },
  { "Sid": "Write", "Effect": "Allow", "Action": ["s3:PutObject"],
    "Resource": ["arn:aws:s3:::BUCKET/7/*"] },
  { "Sid": "List", "Effect": "Allow", "Action": ["s3:ListBucket"],
    "Resource": "arn:aws:s3:::BUCKET",
    "Condition": { "StringLike": { "s3:prefix": ["3/*", "7/*"] } } }
] }
```

Here the user reads projects 3 and 7 and writes only 7. Note the write list is
a **subset**, never computed independently — a project you may write is a
project you may read.

### Deny by default

- **No projects → `403`, not credentials.** An empty session policy denies
  everything, so issuing one would also be safe, but returning nothing says
  what happened and keeps a useless credential out of a browser.
- `project_id` is cast with `Integer()` before it reaches an ARN. These are
  integers from the database, not user input, but interpolating anything into a
  policy document without a cast is the shape of an injection and costs one
  call to rule out.
- The client names **nothing**: not the bucket, not the prefix, not the role.
  The role and bucket come from `config.x`; the prefix is the project id, and
  the source rewrite below is what stops kit data naming either of the first
  two.

## The Active Record side

Almost everything exists. `Project`, `ProjectUser`, `project.member?`,
`project.admin?`, `project.owner?`, and `project_users` already carries
**`admin` and `owner` booleans** with a unique index on
`[project_id, user_id]`.

| | |
| --- | --- |
| new | nothing in the schema — **the "higher role TBD" needs no migration** |
| new | `ProjectUser#may_write_s3?`, one predicate, the single place the TBD decision lives |
| new | `User#s3_read_project_ids` / `#s3_write_project_ids` |
| config | `config.x.s3_bucket`, `config.x.s3_role_arn`, from `S3_BUCKET` and `S3_ROLE_ARN` |

Recommended default for the predicate, to be confirmed:

```ruby
# The "higher role" for write access. Both columns already exist, so this is a
# decision rather than a migration. Defaults to the stricter reading — an
# owner or an admin of the project, nobody else — because the safe direction
# for an undecided permission is deny.
def may_write_s3?
  owner? || admin?
end
```

If it should instead be a named role in `groups` (the way `Portal Managers`
works on `User`), it stays one method; only its body changes.

## Keeping the current mechanism inactive

Nothing existing is edited. The parallel path is additive and separately gated:

| | current | new |
| --- | --- | --- |
| endpoint | `POST /token` | `POST /s3_session` |
| controller | `CognitoTokenController` | `S3SessionsController` |
| server gate | `cognito_configured?` | `s3_sessions_configured?` |
| meta tag | `s3-available` | `s3-sessions-available` |
| client gate | `s3_configured()` | `s3_session_available()` |
| client module | `aws_helper.js` (`fromCognitoIdentity`) | `s3_session.js` (static credentials) |

Both gates are independent, so an instance can have neither, either, or both,
and an instance that configures nothing behaves exactly as `webtrans26` does
today. **`aws_helper.js`, `cognito_token_controller.rb`,
`get_credentials_from_cognito` and the `s3-available` tag are not touched.**

The new client module holds credentials **in memory only** and re-fetches on
expiry — never `localStorage`, which the current path also avoids and which
would outlive the 900 s window.

## The kit source is rewritten, not validated

There is one bucket, so a kit source has no business naming one. Under this
mechanism everything after `s3://` is **key**, and the bucket and the project
prefix are supplied:

```
s3://foo                    →  bucket: <config.x.s3_bucket>   key: <project_id>/foo
s3://foo/bar/take1.wav      →  bucket: <config.x.s3_bucket>   key: <project_id>/foo/bar/take1.wav
```

So in `s3://foo`, `foo` is the prefix *following* the project id. The project
id is the kit's task's — `kit.task.project_id`, and `Task belongs_to :project`
is required, though `tasks.project_id` is nullable in the schema and
`Kit belongs_to :task` is `optional: true`, so both have to be handled rather
than assumed.

This replaces an earlier draft of this section that called for *validating*
that a kit's source prefix matched its project. Rewriting is strictly better:
there is nothing for an operator to get wrong, nothing to migrate, and the
prefix a request carries is **constructed from a database fact** rather than
checked against one. It also makes the earlier claim in this spec — "the client
names nothing: not the bucket, not the prefix, not the role" — true of the
bucket as well, which it was not while kit data named it.

**Nothing is written to the database.** `source_uid` is untouched; the rewrite
happens when a source is resolved. One consequence has to be stated plainly
rather than discovered: an existing source like `s3://my-bucket/recordings/x.wav`
is **reinterpreted**, not migrated — `my-bucket` becomes an ordinary path
component, and the object is looked for at
`<the one bucket>/<project_id>/my-bucket/recordings/x.wav`. That is the rule
applied consistently, and it is why the rewrite must sit behind the same gate
as everything else here: with `s3_sessions_configured?` false, resolution
behaves exactly as it does today.

### Where it cannot go, which is the hard part

The obvious home is the manifest — `task_users_controller.rb` builds
`{ urls: { @kit.source_uid => @kit.source_uid } }` and hands it to the client
to resolve. Rewriting the **value** there looks like a change no client code
would notice. It is not, and the reason is worth tracing before any code is
written: **five places derive a bucket from a kit source string, using two
different parsers.**

| | |
| --- | --- |
| `aws_helper.js:105` | `s3url()`, the shared parser — 13 call sites |
| `aws.js:132` | a **byte-identical duplicate** of it, used by `run_sad` |
| `init.js:229`, `init.js:351`, `helpers.js:123` | a hand-rolled four-line block, **byte-identical in all three**, which takes the bucket from `urls[k]` and the key from **`k`** |

That last row is the trap. It reads the bucket out of one string and the key
out of another, and that is invisible today precisely because the manifest maps
`source_uid` to itself, so `k === urls[k]`. Rewrite only the value and the
three copies take a real bucket from `urls[k]` and then compute
`k.replace(bucket + '/', '')` against a string that no longer contains it —
producing the original `s3://foo` as the key.

And the split is not confined to those three. `set_urlsx` (`init.js:241`)
parses `k` while `set_urls2` (`init.js:220`) parses `urls[k]`; `helpers.js:90`
parses `k` and `helpers.js:97` parses `ldc.resources.urls[k]`, seven lines
apart. **Whether a given site resolves the kit's own name or the manifest's
value for it is currently arbitrary**, and only the identity mapping hides it.
That is the single most important thing to know before touching this, and no
diff would show it.

So the rewrite has to happen somewhere **every** derivation sees the same
string. Either the manifest's key and value are rewritten together, or the five
sites are funnelled through one resolver first. The second is the real fix and
the larger change; the first is smaller and leaves `k` — which is also the
kit's identity in `ldc.obj.source.uid` and in `task_docids` — meaning something
different than it does now. **Settle this before writing anything**, because
both options are cheap to implement and expensive to discover.

Also note `s3url()`'s regex is `/^s3:\/\/([^\/]+)\/(.+)/`, which **requires a
slash**. `s3://foo` returns `{}` today — the canonical example in this section
does not currently parse at all. The new form is `/^s3:\/\/(.+)/`, and the
`{}` return is what the "no bucket in the audio url" alert in `init.js` is
reporting.

### `ldc.resources.bucket` is a channel that already exists, and is empty

`tasks_controller.rb:117` sends `bucket:` to the client, from `@bucket` — which
line 67 hardcodes to `''`, with the real derivation commented out beside it
because the `data_sets` table is gone. The client then **overwrites it** in the
three hand-rolled sites above and in `set_urls3x`. Its one reader is
`services.js:20`, which builds `s3://${ldc.resources.bucket}/${path}` on the
hosted-ASR path that is no longer reachable.

So there is a server→client bucket channel, it carries nothing, the client
writes to it instead, and its only consumer is dead. **It is the natural place
to put the configured bucket and the project prefix** — but it has to be
cleaned up rather than reused as found, or the client's own writes will keep
clobbering it.

**This is still the part most likely to be underestimated.** Not because the
bucket has to be reorganised — the rewrite removes that — but because five
copies of "find the bucket" have to agree, and three of them are the same four
lines pasted in three files.

## Defence in depth, and why both halves are needed

IAM is what *stops* a user; the app check is what makes the refusal legible.
The rewrite removes one whole class of mismatch — a source can no longer name a
prefix the user has no claim to, because it no longer names a prefix at all —
but it does not remove the need for the app check. A kit belonging to project 9
shown to a user who is not in project 9 resolves to
`<bucket>/9/…`, renders fine, and then fails at fetch with an opaque console
error. So:

- filter `s3://` sources and the Browse tab by `s3_read_project_ids`. The
  association to scope from already exists — `User has_many :projects,
  through: :project_users` — and `GroupUser.by_user` is the existing idiom for
  a scope that takes a user id;
- the Browse tab needs more than a filter: `listObjectsV2params`
  (`bucket.svelte:31`, `promise_bucket.svelte:48`) must pass
  `Prefix: "<project_id>/"`, since listing without one asks for the bucket root
  and the session policy's `s3:prefix` condition will refuse it;
- refuse such a kit server-side too.

Neither replaces the policy. The policy is the only thing a determined user
cannot route around.

**The rewrite is not a security boundary and must not be described as one.** It
is a convenience that makes every request land under a prefix the policy
already allows. A client that ignores the rewrite and asks for
`<bucket>/9/x.wav` directly is stopped by the session policy, not by the
rewrite — which is the whole reason the policy is built server-side.

## AWS objects to create

1. **One bucket.** Block Public Access on, default encryption, versioning on,
   and CORS limited to the app's own origin — not `*`, since the browser is
   doing the requests.
2. **One IAM role**, say `webtrans26-project-data`. Permission policy: read and
   write across `BUCKET/*` plus `ListBucket` on the bucket. **Trust policy:
   only the app's own principal may assume it** — its instance role, or the IAM
   user whose keys the app runs with.
3. **Credentials for the app itself**, with `sts:AssumeRole` on that role and
   nothing else. On EC2 this is the instance profile; otherwise
   `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`. The current mechanism needs
   the same thing for Cognito, and `aws/cognito.md` covers it — including why
   the role has to be *attached* to the instance rather than configured in the
   app, since nothing in the repository sets those two variables.

No per-project roles, policies, or pools. That is the point.

## Plan

Each step is independently checkable, and the app behaves as it does today
until step 8.

1. `config.x.s3_bucket` and `config.x.s3_role_arn` from env, plus
   `s3_sessions_configured?` in `Authentication` beside `cognito_configured?`.
   Document both in `docs/CONFIGURATION.md` — it is served at `/documentation`.
2. `ProjectUser#may_write_s3?`, `User#s3_read_project_ids`,
   `User#s3_write_project_ids`. Unit tests; no AWS involved.
3. A policy builder — `S3SessionPolicy.new(user).to_json` or similar — as a
   plain object, so the document can be asserted without a network call. This
   is where the `ListBucket` condition and the `Integer()` cast live.
4. `S3SessionsController#create` + `POST /s3_session`: refuse unless
   `s3_sessions_configured?`, refuse with 403 when the user has no projects,
   otherwise assume the role and return `{ credentials, region, bucket,
   expires_at }`. Log user, projects and expiry.
5. The `s3-sessions-available` meta tag and `s3_session_available()`.
6. `s3_session.js`: fetch on demand, hold in memory, re-fetch on expiry, refuse
   when the gate is false. Mirror `aws_helper.js`'s lazy-fetch comment — it
   records why fetching at import time was wrong.
7. **The source rewrite**, and only after deciding where it lives — see "Where
   it cannot go" above. Whichever way that goes, this step starts by making the
   five bucket-derivation sites one site, because the alternative is making the
   same change five times and discovering the third copy later. The three
   identical hand-rolled blocks are the ones to remove, not to edit.
8. Switch one real consumer over, behind the new gate, and leave the rest on
   the old path.

## Verification

- **Policy documents, asserted as data.** A user in projects 3 and 7, writable
  on 7 only, produces exactly the three statements above. A user with no
  projects produces a 403 rather than a document. These are unit tests and
  need no AWS.
- **The gate, rendered.** `/session/new` with the new config absent must carry
  `s3-sessions-available: false`, and `s3_session_available()` must be false.
  **Render the page to check this** rather than asserting on the helper: a meta
  tag is only as good as the layout that emits it, and a suite that renders no
  pages will pass either way.
- **The rewrite, as a pure function.** `s3://foo` → `(<bucket>, "7/foo")` for
  a kit whose task is in project 7; `s3://foo/bar/take1.wav` →
  `(<bucket>, "7/foo/bar/take1.wav")`. Include **`s3://foo` with no slash**,
  which the current parser returns `{}` for — it is the example this spec is
  written around and the one a regex reused from the old parser will drop. Then
  a kit with no task, and a task with a null `project_id`: both have to do
  something defined.
- **One derivation, not five.** Assert that the hand-rolled
  `urls[k].replace(/^s3(:\/\/)?/, '')` form appears **nowhere** — a grep
  assertion, because the failure mode is a fourth copy rather than a wrong
  answer. This is the test that would have caught the three existing copies.
- **The old path untouched.** `s3-available` and `s3_configured()` behave
  exactly as before with the new config absent, and `aws_helper.js` is
  byte-identical. Assert the byte-identity in the commit, not by eye. With the
  gate off, a kit source resolves to the same bucket and key it does today —
  assert that on a source that names a bucket, since that is the case the
  rewrite reinterprets.
- **Against real AWS**, which no test can replace: a user in one project can
  `GetObject` under their prefix, cannot under another's, can `ListBucket` with
  their prefix, cannot list the bucket root, and cannot `PutObject` without the
  higher role. Four of those five are *negative* tests, and negative tests are
  the only ones that show a policy is doing anything.

## Open questions

- **The higher role.** `owner? || admin?` is the recommendation and the default
  above; a named group is the alternative. One method either way.
- **Delete.** `s3:DeleteObject` is deliberately absent from the write
  statement. Writers who may not delete is the stricter reading; say if it
  should be otherwise.
- **Existing sources that name a bucket.** The rewrite needs no migration,
  but it does reinterpret `s3://my-bucket/x.wav` as a key under the project
  prefix rather than as a bucket and a key. For a fresh instance that is simply
  the rule. For an instance with history it means its objects have to end up at
  `<project_id>/my-bucket/x.wav`, or its kit sources have to be edited to drop
  the old bucket name. Which of those is wanted is a question for whoever has
  the data; the code does not need to know.
- **Where the rewrite lives**, which is the one open question that blocks
  code: the manifest's key and value together, or a single client-side resolver
  the five derivation sites are funnelled through. The second is the better
  end state and the larger change. Nothing else in this spec depends on the
  answer, and step 7 cannot start without it.
- **Whether the old mechanism is ever removed.** The spec keeps it inert, not
  gone. Removing it later is a separate and smaller change, and nothing here
  depends on the answer.
