# User Guide

What every user can do in this application, and what role they need to do it.

This guide is organized in two parts:

1. **Roles** — the glossary of who can do what, in plain terms.
2. **Functionality** — every feature reachable from the UI, with the role gate noted alongside it. UI-first walkthrough; an "API extras" appendix at the end covers anything users can't reach through the dashboard.

---

## 1. Roles

Roles in this app come from three sources: a flag on the `users` row, membership in a built-in `Group`, or a flag on a link table (`project_users`, `task_users`). Higher roles automatically grant lower ones — a system admin is implicitly a portal manager, project owner of every project, project admin of every project, and so on.

### System-level roles

| Role | Source | What it implies |
|---|---|---|
| **System admin** | `users.admin = true` | Top of the hierarchy. Implies *every* role below. Set directly on the `users` row (no UI to elevate someone — has to be done in the DB or a console). |
| **Portal manager** | Membership in the `Portal Managers` group<br>OR system admin | Implies project owner of every project. Effectively a super-administrator with explicit role membership instead of a column flag. |
| **Project manager** | Membership in the `Project Managers` group<br>OR portal manager | Can create new Projects and has elevated read access, but isn't automatically an admin of any specific project. |

The two role-granting Groups (`Portal Managers`, `Project Managers`) are arbitrary `Group` rows whose names are matched against by `User#portal_manager?` / `User#project_manager?`. Anyone in either group automatically gets the corresponding role; both groups are created and managed via the **Groups** dashboard tab.

### Project-level roles

These come from a row in `project_users` linking a User to a Project, with two boolean flags.

| Role | Source | What it implies |
|---|---|---|
| **Project member** | A `project_users` row exists for this user × project | Read access to the project (its tasks, its members). Can be drilled into from the dashboard's **Projects** tab. |
| **Project admin** | `project_users.admin = true`<br>OR project owner of this project<br>OR portal manager (transitively) | Can edit the project, create/delete tasks within it, add/remove project members, set kit_type and workflow on tasks. |
| **Project owner** | `project_users.owner = true`<br>OR portal manager (transitively) | Can rename the project, transfer ownership. Project owners are also project admins by definition. |

A project member who isn't admin/owner is read-only at the project level — they can see what's there but not change anything.

### Task-level roles

These come from a row in `task_users` linking a User to a Task, with one boolean flag.

| Role | Source | What it implies |
|---|---|---|
| **Task member** | A `task_users` row exists for this user × task | The user is *eligible* to receive kits from this task and see them in their **Work** tab. |
| **Task admin** | `task_users.admin = true`<br>OR project admin of the task's project (transitively) | Can edit the task (rename, change status, change workflow, change kit_type), see all kits including others' done kits, download transcripts, manage task members. |

### Per-kit roles

There's no separate "kit role" — access to a kit is derived from the task it belongs to:

- A kit is **assigned** to a specific user (`kits.user_id`); only that user can edit it via the annotation tool. They keep that lock until they mark it Done, Broken, or Skip.
- Anyone who is task admin (or higher) can view any kit in the task in **read-only** mode (`/workflows/<workflow_id>/read_only/<kit_uid>`).

### Quick reference: "who can do what"

For a feature gated on each role, *anyone at or above that level* can do it.

```
                       system admin
                            │
                       portal manager  ←── grants every project-level role on every project
                            │
                       project manager
                            │
       ┌────────────────────┼────────────────────┐
       │                    │                    │
   project owner       project admin         (signed-in user)
       │                    │
       └────────┬───────────┘
                │
            task admin   ←── transitively grants this on every task in the admin'd project
                │
            task member
```

---

## 2. Functionality

### 2.1 Sign-up, sign-in, and account

The auth surface is small and entirely available to anyone (signed in or not), since the whole point is to *get* you signed in.

#### Create an account ([signed-out only])

| What | Where | Notes |
|---|---|---|
| Open the sign-up form | "Create account" link on `/session/new`, or visit `/signup` directly | |
| Submit name, email, password, password confirmation | Form on `/signup` (POSTs to `/signup` → `users#create`) | Username: 1–30 chars, letters/digits/`_`/`-`/`.`, case-insensitive unique. Email: standard format, max 255, case-insensitive unique. Password: ≥ 8 chars. |
| Receive activation email | `UserMailer.account_activation` is sent automatically on successful sign-up | The email contains a single link to `/account_activations/<token>/edit?email=…` that activates the account. **Exception:** in the `development` environment the account is auto-activated and the user is signed in immediately — no email step. |

#### Activate the account ([signed-out, link from email])

| What | Where | Notes |
|---|---|---|
| Click the activation link | `GET /account_activations/<token>/edit?email=…` (`account_activations#edit`) | Sets `users.activated = true` and stamps `activated_at`. Until this step succeeds, sign-in fails with *"Your account hasn't been activated yet."* |

#### Sign in / Sign out

| What | Where | Notes |
|---|---|---|
| Sign in | `/session/new` (form POSTs to `/session` → `sessions#create`) | Requires email + password. **Rate-limited** to 10 attempts per 3 minutes per IP — exceeding it triggers *"Try again later."* On success, redirects to the user's dashboard (`/users/<id>`). Account must be activated. |
| Sign out | `DELETE /session` → `sessions#destroy` | Terminates the current session and redirects to `/session/new`. Available wherever the dashboard renders a sign-out control. |

#### Reset password (and optionally rename) ([signed-out, no role required])

| What | Where | Notes |
|---|---|---|
| Request a reset link | "Username/password recovery" link on `/session/new`, or `/passwords/new` directly (form POSTs to `/passwords` → `passwords#create`) | Sends `PasswordsMailer.reset` to the email address *if* one matches, but the page always shows the same notice (*"Password reset instructions sent (if user with that email address exists)."*) regardless — so an attacker can't enumerate users. |
| Set a new password | Click the reset link in the email → `/passwords/<token>/edit` (form PUTs to `/passwords/<token>` → `passwords#update`) | The form lets you update **password + password confirmation** *and* the **username**. Token is single-signed and expires; an invalid/expired token redirects back to `/passwords/new` with *"Password reset link is invalid or has expired."* |

#### View own profile / dashboard ([signed-in user only])

| What | Where | Notes |
|---|---|---|
| Open dashboard | `/users/<your-own-id>` (`users#show`, `correct_user` filter) | The only profile page in the app, and the only place to start working on tasks. Even a system admin gets *"you can't access other users' profiles"* if they try `/users/<other-id>` — the gate only allows the user themselves. |

#### Things you can't do through the UI

These exist as concepts in the data model but no UI exposes them:

- **Change your email address** — there's no `users#edit` / `users#update`. The address you signed up with is permanent; reset flow doesn't change it either.
- **Delete your own account** — no `users#destroy` either.
- **Promote yourself or anyone else to system admin** — `users.admin = true` has to be set in the DB or a Rails console.
- **Become a portal manager / project manager** — those come from joining the `Portal Managers` / `Project Managers` Group, which only an existing portal-manager-or-higher can do (via the **Groups** dashboard tab — see the next section).

### 2.2 Dashboard top-level tabs

The dashboard at `/users/<your-id>` is a single page with ten top-level tabs along the top, plus **Activations** for portal managers. Every other tab is *visible* to every signed-in user — what changes is what's *populated* and what *actions* you can take inside.

The "Set yourself to …" buttons under the **Permissions** tab only ever *downgrade* what the front-end thinks your role is for the rest of that browser session — they never write to the server. So they're useful for previewing what the dashboard looks like to a less-privileged user, but you can't grant yourself any role this way.

#### 2.2.1 Work

The default landing tab (renamed to "Work" in the trigger; the value is `tasks` internally).

| What | Role required |
|---|---|
| See your task list — every task you're a member of (a `task_users` row exists), with columns Project / Task / Action / Status / Done Kits | Signed-in user. Rows show only the tasks the *viewing* user is a member of, regardless of their other roles. |
| Click a row's **Action** link to start (or continue) work on a task | Signed-in user, must already be a task member of that row's task. The link is `/workflows/<task_user_id>/work/<workflow_id>` and lands you in the annotation tool. |

There's no Create button on this tab — task membership is granted from the **Project Tasks** sub-tab (see §2.3) by a project admin.

#### 2.2.2 Projects

| What | Role required |
|---|---|
| See the projects table | Signed-in user. **Project manager** sees *all* projects; everyone else sees only the projects they're a member of (`project_users.user_id` matches). The label above the table flips between "All Projects" and "My Projects" accordingly. |
| Open a project (drills into Project Info / Project Tasks / Project Members sub-tabs — see §2.3) | Signed-in member of that project. |
| **Create Project** | Project manager. The trigger renders only if `lead_annotator` (= project manager) is true. |
| **Delete Project** (after selecting one) | System admin. The Delete trigger only appears when `admin` is true. |

#### 2.2.3 Browse

Currently inactive — the tab renders the literal text `deactivated`. The Browse component (file/source explorer) was unwired pending a rewrite.

#### 2.2.4 Kit Types

A Kit Type is the template that defines a Task's annotation tool, available constraints, and which `NodeClass` is its tree root.

| What | Role required |
|---|---|
| See the Kit Types table (ID + Name) | Signed-in user. |
| Open a Kit Type (drills into Info / Members sub-tabs) | Signed-in user (read access). |
| Edit a Kit Type's name, description, JavaScript template, root NodeClass, etc. | Project manager (the patch endpoint requires `project_manager?` on the back end). |
| **Create Kit Type** | Project manager. Trigger gated on `lead_annotator`. |
| **Delete Kit Type** (after selecting one) | System admin. Gated on `admin`. |

#### 2.2.5 Features

A Feature is a named option (with a category, value, label, description) that can be attached to other entities — currently used for task-level toggles.

Same gating as Kit Types:

| What | Role required |
|---|---|
| See the Features table | Signed-in user. |
| Open / view a Feature | Signed-in user. |
| Edit a Feature | Project manager. |
| **Create Feature** | Project manager. |
| **Delete Feature** | System admin. |

#### 2.2.6 Workflows

A Workflow is the kit-assignment strategy a Task uses:

- **`Orderly`** — kits already exist (made on the **Kits** tab); the workflow hands out the oldest unassigned one.
- **`OnTheFly`** — a new kit is created from the task's own `docid` every time, so the same audio is worked over and over.
- **`SameListForEveryone`** — the task carries a list of documents (the **Docid List** tab, §2.4.7) and every user of the task works that same list.

Same gating as Kit Types:

| What | Role required |
|---|---|
| See the Workflows table | Signed-in user. |
| Open / view a Workflow | Signed-in user. |
| Edit a Workflow | Project manager. |
| **Create Workflow** | Project manager. |
| **Delete Workflow** | System admin. |

#### 2.2.7 Groups

Groups are arbitrary collections of users. Two of them have special meaning: `Portal Managers` and `Project Managers` — membership in either grants the matching system-level role.

| What | Role required |
|---|---|
| See the Groups table | Signed-in user. |
| Open a Group (drills into Group Info / Group Members sub-tabs) | Signed-in user. |
| Edit a Group's metadata (name, description, type) | Project manager. |
| Add a user to a Group / remove a user / toggle a member's admin flag inside the group | Project manager (and there's no separate "group admin" role beyond that). Adding someone to `Portal Managers` or `Project Managers` is therefore the canonical way to grant those system-level roles. |
| **Create Group** | Project manager. |
| **Delete Group** | System admin. |

#### 2.2.8 Invites

Send an email invitation that pre-creates an account.

| What | Role required |
|---|---|
| Open the tab and see the invitations you've made | **Project manager.** Anyone else sees the literal text *"Not allowed"*. |
| Send a new invite (email, optional starting role, optional pre-assignment to a project + task) | Project manager. The role-radio in the dialog only offers tiers ≤ your own: project managers can invite a normal user; portal managers can also invite a Project Manager; admins can also invite a Portal Manager. |
| See an invite's status (Sent / Activated) | Project manager. |

> The send-invite dialog is currently commented out in the client, so `POST /invites`
> has no caller. On an instance without working outbound mail, use **Access links**
> below instead.

##### Access links (no email required)

At the top of the same tab, for **portal managers and system admins** only. Creates
the account and hands you a URL to pass on however you like — chat, phone, paper.

| What | Detail |
|---|---|
| **Create Link** (name + email) | Creates an inactive account with a random password nobody needs to know, and returns a link. `POST /access_links`, gated on `portal_manager?` (which includes admins). |
| The link | `/access/<user id>/<token>`. Opening it activates the account, starts a session, and signs the person straight in — no password prompt. |
| **Single use** | The click clears the stored digest, so the same URL won't work twice. A refresh, a second click, or a later sign-out all mean the user needs a new link. |
| Re-issuing | Creating a link for an address that already exists doesn't make a second account — it issues a fresh link for that user and keeps their name. This is the recovery path for someone who signed out. |
| **Links not used yet** table | Name / Email / Created / By, for every account with an outstanding link. Rows disappear once the link is spent. |

Only the token's digest is stored, so the URL is shown exactly once, when you create
it — there's no way to look it up afterwards. If you lose it, create another.

Treat a live link like a password: anyone holding it becomes that user on first
click. The alternative to a new link is the ordinary password-reset flow
(§2.1), which on a mail-less instance parks the account until an admin reactivates it.

#### 2.2.9 Permissions

A read-only display of your current system-level role plus "preview as a lower role" buttons.

| What | Role required |
|---|---|
| See your current role label (*"You're an Admin."* / *"… a Portal Manager."* / *"… a Project Manager."* / *"You don't have any global permissions."*) | Signed-in user. |
| Click **"Set yourself to <lower role>"** | Signed-in user. **Important:** this only mutates the in-memory Svelte state for the current browser session. It does *not* change `users.admin` or your group memberships. Refreshing the page restores your real role. The button is there so admins can sanity-check what less-privileged users see. There's no upgrade direction. |

#### 2.2.10 Account

Your own settings. Visible to every signed-in user.

| What | Detail |
|---|---|
| **Change password** (current password, new password, confirmation) | Requires your existing password, so a borrowed browser can't quietly change it. The new one must be at least 8 characters and match its confirmation. `PATCH /account/password`, which requires authentication and is rate-limited to 10 attempts per 3 minutes. |
| Other devices | A successful change destroys every other session for your account and tells you how many — the current browser stays signed in. That's how you evict a device you no longer control, or retire a spent access link. |

Forgotten passwords are a different path: sign out and use the reset flow (§2.1),
which on an instance without outbound mail parks the account until an
administrator reactivates it, or ask an administrator for an access link
(§2.2.8).

### 2.3 Project drill-in

To get here: **Projects** tab → click a project row → **Open** (boiler3) — *or* the equivalent **Open Project Info** / **Open Task List** buttons. The drill-in adds a second row of tabs for that one project: **Project Info** / **Project Tasks** / **Project Members**.

To even reach the drill-in you must be a **project member** (a `project_users` row exists). Project managers see all projects in the table and can drill into any of them; non-managers only see projects they're a member of, so the drill-in is implicitly gated by membership for them.

#### 2.3.1 Project Info

| What | Role required |
|---|---|
| See ID and name | Project member. |
| **Rename** the project (inline-editable Name field) | **Project owner.** The Patch input only renders when the server response says `project_owner_bool: true`; non-owners see a read-only "Name: …". The PATCH `/projects/<id>` endpoint also enforces this server-side via `project_owner_user`. |

There's no other field on Project Info — projects only have ID and name in the schema. Most of the metadata that varies *per project* lives on its tasks.

#### 2.3.2 Project Tasks

| What | Role required |
|---|---|
| See the task table (ID / Task / Available Kits / Source UID) | Project member. The header reads **"All Tasks"** for project admins and **"My Tasks"** for non-admins, but in both cases the rows are *all* tasks on the project — the label is just a UI hint, not a filter. |
| Open a task (drills into Task Info / Kits / Done Kits / etc. — see §2.4) | Project member. The contents of those task sub-tabs *are* gated further (e.g. Kits requires task admin) — see §2.4. |
| **Create Task** (dialog: name, then defaults) | **Project admin.** Trigger gated on `project_admin_bool`. New tasks default to workflow=`OnTheFly` and a fresh per-task `KitType` (with `web_audio` + `show_source` constraints) if those aren't specified. The POST `/projects/<id>/tasks` enforces `project_admin?`. |
| **Delete Task** (after selecting one) | **Project admin.** Trigger gated on `project_admin_bool`. The DELETE `/projects/<id>/tasks/<task_id>` endpoint enforces `project_admin?`. |

The "Open" + "Open Task Info" / "Open Kit List" buttons under the table appear once a row is selected (boiler7 on the task model). "Open Task List" is the same as the parent action; it's there for symmetry.

#### 2.3.3 Project Members

A two-pane layout: the members table on the left, an editor pane on the right.

| What | Role required |
|---|---|
| See the members table (User ID / Name / Owner / Admin) | Project member. Server returns the full member list to anyone who's a member. |
| **Add Member** dialog (autocomplete of users not already in the project, click to invite) | **Project admin.** The Add trigger renders only when `project_admin_bool` is true. POST `/project_users` enforces `project_admin?` server-side. |
| **Remove Member** dialog (after selecting a member) | **Project admin.** Trigger gated on `project_admin_bool` AND a selected user. DELETE `/project_users/<id>` enforces `project_admin?`. |
| Toggle the **Owner** checkbox on a selected member | **Project owner.** The right-pane editor only renders when `project_owner_bool` is true. PATCH `/project_users/<id>` enforces `project_owner?` for *both* fields below. |
| Toggle the **Admin** checkbox on a selected member | **Project owner.** Same gate as Owner above. |

Practical implication: a project admin who *isn't* an owner can add or remove members, but they can't promote anyone to admin/owner — that takes the project owner. (Or any portal manager / system admin, who get project owner transitively.)

### 2.4 Task drill-in

To get here: **Project Tasks** sub-tab → click a task row → **Open Task Info**. The drill-in adds a third row of tabs for that one task: **Task Info** / **Kits** / **Done Kits** / **Sources** / **Duals** / **Task Members** / **Docid List** / **Batches** / **Nodes** / **New Batches**.

To even reach the drill-in you must be a project member of the task's project (since you got here through the project drill-in).

#### 2.4.1 Task Info

| What | Role required |
|---|---|
| See ID and Name | Project member. |
| **Edit** the full set of task settings: Name (rename), **Status** (active/inactive), **Workflow** (dropdown of all workflows), **KitType** (dropdown of all kit types), **DataSet** (dropdown), plus a per-feature row for every `Feature` row of category `task` — e.g. `docid`, `1p_task_id`, `dual_percentage`, `dual_minimum_duration`, plus arbitrary checkbox-style features | **Project admin.** Boiler5 only renders the editable form when `project_admin_bool` is true; non-admins see only the read-only "ID: …" and "Name: …" pair. The PATCH `/projects/<pid>/tasks/<tid>` enforces `task_admin?` (which includes project admins transitively). |

#### 2.4.2 Kits

A two-mode tab: a kits table on its own, then a per-kit detail panel once you select a row.

| What | Role required |
|---|---|
| See the kits table (ID / UID / State / Source / Continue link / User / Broken Comment / Updated At) | Project member of the task's project. The header label says "All Kits" for task admins and "My Kits" for everyone else, but the rows are the same set. (`/kits/task/<tid>` returns all kits.) |
| Filter the table by **State** or **User** (filter pills) | Anyone who can see the table. Filters are client-side. |
| Click a row → **Open** the kit's detail panel (shows ID, UID, **User** dropdown to reassign) | Project member can see; **task admin** to actually change the User assignment via the User dropdown. The Patch on the dropdown calls PATCH `/kits/<id>/update`, which enforces `task_admin?`. |
| **Create Kits (Text Input)** dialog — paste docids, parse, create | **Task admin**, enforced by `/create_kits_from_kits_tab` as well as by the trigger only rendering when `vv.task_admin_bool`. See below for what a line may say. |
| **Create Kits (File Input)** dialog — upload a file of the same lines, parse, create | Task admin, same endpoint and the same line format as above. A file starting with `[` or `{` is read as JSON kit objects instead. |
| **Bulk Reassign** dialog — change user/state on every filter-matched row | Task admin. |
| **Download Transcript** dialog — generate a zip of TSV transcripts (one per kit) for the whole task | Task admin. Trigger gated on `vv.task_admin_bool`. The data-providing endpoint `/kits/all?task_id=…` has no admin gate server-side, but the dialog calls `Kit#snapshot` per-kit at request time, so a non-admin reaching the URL directly still gets data. |

##### Creating kits from a list

One kit per line. The line starts with the docid — whatever this task's kits use as their source, an `s3://` url, a path or a bare name — and may then say who the kit is for:

```
s3://my-bucket/recordings/REC_one.wav
s3://my-bucket/recordings/REC_two.wav user_id=alice
s3://my-bucket/recordings/REC_three.wav user_id=alice@example.org
```

`user_id` accepts a user's id, name or email address, whichever you have to hand. A kit made with one belongs to that person: the workflow gives it to them and to nobody else. A line without one makes an ordinary unassigned kit, which goes to whoever asks for work next.

The **File Input** dialog reads a file of exactly these lines — upload it, then **parse as text**. A file whose first non-blank character is `[` or `{` is read as JSON kit objects instead.

**Parse as text** shows what each line was read as before anything is created. A line that can't be read — a field that isn't `user_id`, a word with no `=`, a `user_id=` with nothing after it — is reported there and blocks the Create button, so a typo doesn't quietly make fewer kits than you asked for.

A line naming a user who doesn't exist makes **no kit at all**, and is reported back after creating: a kit owned by nobody is indistinguishable from an ordinary unassigned one and would go to the wrong person. What was created, and what wasn't, appears above the kits table.

#### 2.4.3 Done Kits

| What | Role required |
|---|---|
| See the done-kits table (ID / UID / Source / User / Done Comment) | Project member. Header reads "All Done Kits" for task admins, "My Done Kits" otherwise; rows are server-filtered to `state == 'done'` but otherwise the same set. |
| Click a UID to open the kit in **read-only** mode (`/workflows/<workflow_id>/read_only/<kit_uid>`) | Project member. The read-only viewer has its own access check (`task_users#read_only`) which currently allows anyone with a session. |

There's no Done-Kit-specific create/delete; this tab is read-only.

#### 2.4.4 Sources

The same kit list as the Kits tab, rolled up **per source** instead of per kit —
"who has finished this piece of audio, and how many people".

| Column | Meaning |
|---|---|
| **Source** | A unique `source_uid` among the task's kits (`none` for kits without one). |
| **Users Done** | How many *distinct* users have at least one kit for that source in the `done` state. A user with several done kits on the same source counts once. |
| **Who** | Those users, by name, alphabetically. Empty when nobody has finished it. |
| **Done Kits** | Done kits for that source (can exceed **Users Done** — the same user may have several). |
| **Kits** | All kits for that source in this task, in any state. |

Every source in the task gets a row, including ones nobody has finished yet
(**Users Done** 0). The table sorts by clicking a column header, filters with the
search box, and its download button exports the rows as TSV.

Same access as Kits / Done Kits: any project member, reading `/kits/task/<id>` and
aggregating client-side (`app/javascript/components/kit_sources.js`). Unassigned
done kits — where the server reports the user as the string `none` — are counted in
**Done Kits** but contribute no user.

##### Comparing annotators on one source

Click a source row and the table is replaced by a read-only comparison of every
**done** annotation of that source — no waveform, no editing. **Return to source
list** goes back.

It reads like a transcript: **one line per segment**, showing that segment's own
times, the annotator who wrote it, and the text. No line ever mixes two
annotators.

Lines are grouped into **blocks** separated by a rule. A block is a stretch of
audio: all the annotators' segments go on one timeline, and those that overlap —
directly or through a chain of overlaps — land in the same block, so versions of
the same audio read together even when annotators segment differently. Within a
block, lines run in time order. Segments that merely touch at an endpoint start a
new block, matching the reference-caption rule in the editor.

```
Time          Annotator   Text
─────────────────────────────────────────────
0.50–4.60     alice       that's carrie fisher
0.52–4.58     bob         That's Carrie Fisher
─────────────────────────────────────────────
4.80–6.60     alice       as princess leia          ← block highlighted:
4.79–5.30     bob         as Princess                 they disagree
5.30–6.61     bob         Leah
```

Blocks where the annotators disagree are highlighted, with the count above the
table. Disagreement is judged per annotator over everything they said in the
block, so one person splitting a sentence in two isn't a disagreement with
someone who kept it whole. Case, punctuation, and runs of whitespace are ignored,
so *"That's Carrie!"* and *"thats carrie"* agree. A block only one annotator
covered is a gap, not a disagreement.

Only done kits appear, since the transcripts come from `/kits/all` (the same
endpoint the Download Transcript dialog uses), which filters to `state = 'done'`.
An annotator whose done kit has no segments contributes no lines but still counts
in the annotator total. The alignment itself is
`app/javascript/components/source_comparison.js`.

#### 2.4.5 Duals

Currently inactive — renders the literal text `duals`. The component is commented out.

#### 2.4.6 Task Members

A two-pane layout (members table on the left, per-member editor on the right) — same shape as Project Members.

| What | Role required |
|---|---|
| See the members table (User ID / Name / State / Admin) | Project member. |
| **Add Member** dialog (autocomplete of users not already on the task) | **Task admin.** Trigger gated on `task_admin_bool`. POST `/task_users` enforces `task_admin?`. |
| **Add Members from Task** dialog (choose another task; every one of its members is added to this one) | **Task admin of both tasks.** Trigger gated on `task_admin_bool`. POST `/task_users/copy_from_task` enforces `task_admin?` on the destination *and* checks you administer the source, so another task's member list isn't readable to anyone who merely admins some task. |
| **Remove Member** dialog (after selecting a member) | **Task admin.** DELETE `/task_users/<id>` enforces `task_admin?`. |
| Toggle the **Admin** checkbox on a selected member | **Task admin.** The right-pane editor renders when `task_admin_bool` is true. PATCH `/task_users/<id>` enforces `task_admin?`. |
| Change the member's **State** (`needs_kit` / `has_kit` / `hold` / `paused`, plus `null`) | Task admin. Same PATCH endpoint and gate. |

Unlike projects (where promoting to admin/owner needs the owner), promoting another task member to task admin only needs *task admin*. Practical effect: any task admin can hand the keys to anyone else.

##### Adding everyone from another task

Setting up a second task for the same group of annotators is the common case, and adding them one at a time is the slow way. **Add Members from Task** lists every task you administer — the ones you're a task admin of, plus every task in a project you admin or own — with its project and how many members it has, and adds all of them to the task you're looking at.

What it copies is *membership*, and only that:

- Someone who is an **admin** of the other task is added here as an ordinary member. Admin is granted per task, and copying it would hand out rights nobody asked for.
- Their **state** starts fresh (`null`), the same as anyone added by hand — so the workflow gives them their first kit rather than carrying over where they'd got to elsewhere.
- Anyone **already a member** is left exactly as they are. Nothing is overwritten and it isn't an error, so you can run the same copy again after the other task gains people.

The dialog reports what happened — who was added, and who was already there — and stays open so you can read it. The members table behind it refreshes when you close the dialog.

The task you're looking at isn't on its own list, and a task you don't administer isn't either.

#### 2.4.7 Docid List

The list of documents this task hands to **every** one of its users. One docid per line — whatever this task's kits use as their source (an `s3://` URL, a path, a bare id).

| What | Role required |
|---|---|
| See the list | **Task admin.** Non-admins get *Permission Denied* in the tab; GET `/task_docids` returns it. |
| Edit and **Save list** | **Task admin.** POST `/task_docids` enforces `task_admin?`. |

Saving replaces the whole list. Blank lines, stray whitespace and repeats are dropped, and the box redraws with the list as stored — so what you see afterwards is what was kept, not what you typed.

The list only does anything when the task's **Workflow** is `SameListForEveryone` (set on **Task Info**). Under any other workflow it's ignored, and the tab says so rather than hiding — a list is usually entered before the workflow is switched over.

Under that workflow, when a user comes for work and has no kit waiting, a kit is created for each document on this list they haven't had yet, and they're given the first of them. So:

- Every user of the task works the same documents, each in their own kits.
- A user part-way through the list just gets their next kit; nothing new is created.
- A user who has finished the list stays finished — it's a list, not a supply of work. Their **Work** tab then reads *No Available Kits* for that task.
- Before a user starts, the task has no kits at all: they're made when the user arrives. The **Work** tab still offers **Start Now**, because what's left is judged by the list rather than by counting kits that don't exist yet.
- The **Available Kits** column on the Project Tasks table counts the same way — every document each member is still owed, plus any kits already waiting. A task with a list of 10 and 4 members reads 40 before anyone starts.
- A document **added** to the list later reaches everyone, including people who had already finished.
- A document **removed** from the list is not handed out again, and kits already made from it are left alone.

#### 2.4.8 Batches / Nodes / New Batches

All three are currently inactive — they render the literal text `batches` / `nodes` / `nb`. The components are commented out (Batches / Nodes / NewBatches), but the placeholder source notes that when they're re-enabled they'll require `project_admin || lead_annotator || task_admin`.

### 2.5 Annotation tool

You enter the annotation tool by clicking the **Action** link on a row in the **Work** tab — that lands you at `/workflows/<task_user_id>/work/<workflow_id>` (`task_users#get`). The server runs the task's workflow's `work` method, assigns or auto-creates a kit if needed, and renders the work page.

To even reach the page you must be a **task member of the kit's task** (a `task_users` row exists), and the assigned kit's `user_id` must equal yours — which is what the workflow set up. Trying the URL with someone else's `task_user_id` redirects to the dashboard with *"wrong user"* (or, if you're a system admin, drops you into read-only mode for that kit).

#### 2.5.1 Page layout

Top to bottom:

| Region | What's there |
|---|---|
| **Header strip** | Source filename · selection start/end · muted indicator · playback-speed buttons (0.5×, 0.8×, 1×, 1.5×, 2×, 3×) · upload (⬆) · download (⬇) · close-kit (✓) · keyboard-help icon · home (House icon) link |
| **Waveform** | Canvas-rendered audio. Click to set cursor; drag to set selection. The page on first load downloads the audio for your kit's `source_uid`. |
| **Segments table** | One row per `SegmentListItem` in the tree. Sorted by `beg` time. Columns: speaker · begin · end · text (editable when active) · section. Click a row to make it the active segment. |
| **Hidden help screen / input modal / settings dialog** | Reveal by keystroke; covered below. |

#### 2.5.2 What you can do (gated by kit-type constraints)

These four header buttons are individually feature-flagged on the **kit type's** constraints (set by a project admin in §2.4.1's Task Info panel — the Features panel pulls these in from the `Feature` rows of category `task` / `kit_type`).

| Button | Always visible? | Gate |
|---|---|---|
| **⬆ Upload transcript** | Only if visible | `constraint_import_transcript` is set on the kit type, **or** the viewer is a project manager. Opens the upload-transcript dialog (paste TSV / load from file / auto-import via service). |
| **⬇ Download transcript** | Only if visible | The kit type has `constraint_export_transcript` set, **or** the viewer is a project manager, **or** (`constraint_export_transcript_to_task_admin` is set AND viewer is a task admin). Opens the in-tool download dialog (filename + Include Headers / Speaker / Section checkboxes → Create Preview → Download File). |
| **✓ Close kit** | Always visible | No role gate beyond being the kit's assignee. The dialog flavour depends on `constraint_audit`: with audit, a popover with "Done comment Yes/No/Maybe" radios; without audit, a modal with "✓ Done", optional comment textarea, and "Skip / Broken" radios. |
| **💬 Comments** | Only if visible | The kit type has the `comments` constraint set. Shows or hides the comments panel under the transcript — see §2.5.6. |
| **Keyboard / Home** | Always | Help & navigation. |

#### 2.5.3 Modes and the keyboard

The waveform has three keyboard modes. The active mode determines what each key does. Press **Esc** or **/** in any mode to open the mode picker. Most users live in **cursor** mode.

**Cursor mode** (default):

| Key | Action |
|---|---|
| `Space` | Play current span / stop |
| `Enter` | Add a new transcript line for the current selection (creates a SegmentListItem with Arc + Text) |
| `,` | Split the active segment at the cursor |
| `m` | Merge the active segment with the next |
| `Tab` | Focus the text input (switches to "input mode"). With no segment active — you clicked the waveform rather than a line — it takes the segment the cursor is in, or the next one after it, and selects that segment's audio, exactly as clicking the line would. |
| `i` / `o` | Zoom in / out |
| `z` | Toggle zoom |
| `r` | Refresh waveform |
| `b` / `e` | Switch to "selection-from-beg" / "selection-from-end" mode |
| `w` | Switch to window mode |
| `f` `d` `s` `a` | Move cursor left, increasing step (~30ms / 100ms / 500ms / 2s) |
| `j` `k` `l` `;` | Move cursor right, increasing step (same scale) |
| `↑` / `↓` / `n` | Active line: previous / next / next |
| `q` | Settings |
| `h` | Show help screen |
| `D` (Shift+D) | Delete-all confirm |
| `u` | Upload transcript |
| `0` | Open spectrogram |

**Window mode** (`w` from cursor): same `f d s a j k l ;` keys move the **visible window** instead of the cursor. `c` returns to cursor mode.

**Selection mode** (`b` or `e` from cursor): same `f d s a j k l ;` keys move the **selection's left or right edge**. `c` returns to cursor mode.

**Input mode** (when a segment textarea is focused — entered via `Tab` or by clicking on a segment row):

| Key | Action |
|---|---|
| Plain typing | Edits the segment's text (debounced save after 1s, flushes on blur) |
| `Esc` / `/` | Open mode menu |
| `Enter` | Move active line to next, play current span |
| `Tab` | Refocus the keyboard div (leave input mode) |
| `↑` / `↓` | Previous / next active line |
| `Ctrl+Space` | Play current span |
| `Ctrl+,` | Split at cursor |
| `Ctrl+m` | Merge with following |
| `Ctrl+s` | **Set speaker** (opens speaker help screen → press `n` for new → input screen → type → Enter; or press the assigned letter for an existing speaker) |
| `Ctrl+[` | **Open section** (opens section help screen → `n` for new → type → Enter) |
| `Ctrl+]` | **Close section** (extends the current section to include the active segment) |
| `Ctrl+\` | Show all sections |
| `Ctrl+v` | Validate transcript |
| `Ctrl+p` | Play head menu |
| `Ctrl+n` | Generic next |
| `Ctrl+r` / `Ctrl+u` / `Ctrl+l` / `Ctrl+g` | Wrap selection in tag: redact / unintelligible / laugh / sing |
| `Ctrl+j` | Add to (segment list) |
| `Ctrl+d` | Delete the active line (with confirm) |

Pressing any unmapped key in cursor mode opens the help screen.

On a kit whose kit type sets `transcribe_text_only` (§2.5.7), the keys that would change the transcript's *shape* — `Enter`, `,`, `m`, `D`, `u`, `Ctrl+d`, `Ctrl+,`, `Ctrl+m`, `Ctrl+j`, `Ctrl+s`, `Ctrl+[`, `Ctrl+]`, `Ctrl+\` — do nothing, and the cheat sheet (`h`) shows them struck through.

#### 2.5.4 Closing the kit (Done / Broken / Skip)

The ✓ icon opens the close-kit dialog. Three terminal states:

| Action | Effect | Role required |
|---|---|---|
| **Done** | Marks the kit `state='done'`, writes a `message='done'` Annotation. Frees the assignee. | Kit assignee. |
| **Broken** (after radio + optional comment) | Marks the kit `state='broken'`, writes a `message='broken'` Annotation with the comment. | Kit assignee. |
| **Skip** | Writes a `message='skip'` Annotation; workflow normally re-assigns a different kit. | Kit assignee. |

There's no role gate beyond "you're the assigned user" — the workflow only opened this kit for you in the first place.

#### 2.5.5 Read-only mode

Reachable directly via `/workflows/<workflow_id>/read_only/<kit_uid>` (`task_users#read_only`) — used when a system admin views someone else's in-progress kit, or when clicking a UID link in the Done Kits table. The same waveform/segments UI, but **all save endpoints reject** with `read_only=true` set on the kit object client-side. No keyboard shortcut creates segments or edits text in read-only mode.

#### 2.5.6 Comments ([kit type sets `comments`])

A comment is a remark about a stretch of audio — "speaker coughs here", "two people at once", "check this against the recording". It is **not** transcript: no transcript download, export or dashboard view includes comments, and adding one never changes the transcript.

The 💬 button in the header shows and hides the comments panel, which sits under the transcript. From the panel:

| What | How |
|---|---|
| Add a comment | Select a stretch of the waveform (or click a segment, and it uses that segment's span) and press **Comment on selection**. A row appears with the cursor already in it. |
| Write it | Type. It saves a second after you stop, the same way a segment's text does. Leaving the box or pressing `Enter` saves straight away; `Esc` abandons what you just typed. |
| Play the stretch it covers | Click its time range. |
| Remove it | The **×** at the end of its row. |

There's no keyboard shortcut — the panel's button is the only way in, so no key changes meaning when comments are switched on.

Comments are allowed even on a kit where the transcript itself is locked (§2.5.7): being unable to change the transcript's shape shouldn't mean being unable to note something about the audio.

#### 2.5.7 Transcribing an imported transcript ([kit type sets `transcribe_text_only`])

For work where the segments are decided in advance and the annotator's job is only to type what's said.

The kit type carries the `transcribe_text_only` constraint, and its **value** names which imported tier to read (`reference` if left as the default). When the kit opens, the tool finds the imported transcript whose document matches the kit's audio — matched on the file's stem, so a missing or extra `.wav`, a directory, or an `s3://` prefix makes no difference — and:

- Each imported span is shown as a **blue prompt** above the line you type into.
- On a kit with no segments yet, a segment is created at each imported span's times, empty. This happens once; coming back to the kit later doesn't create them again.
- From then on, **only the text may change**.

What that rules out — whether by key, by button, or by any other route:

| Not available | Why |
|---|---|
| Creating a segment | The imported spans are the segments. |
| Splitting, merging, deleting | The number of segments is fixed. |
| Moving a segment's start or end | The times are the imported ones. |
| Speaker, section | Neither is part of this kind of work. |

Comments (§2.5.6) remain available if the kit type also sets `comments`.

If no imported transcript matches the kit's audio, the tool says so in red under the waveform and leaves the kit alone — nothing is created and nothing is locked. The message names the tier it looked for *and* the tiers that document does have, which is usually the answer (a list imported as `ref` where the kit type asks for `reference`).

**Importing the transcripts themselves is not a dashboard feature.** They are loaded from a TSV on the server, by someone with shell access:

```bash
bin/rails imported:plan FILE=transcripts.tsv          # what it would store, storing nothing
bin/rails imported:tsv  FILE=transcripts.tsv NAME=reference
```

One file may hold many documents — a column names which — and each becomes its own imported transcript. `bin/rails imported:list` shows what's stored, and `imported:clear` takes an import back out.
