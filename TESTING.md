# Testing

The test suite has four layers. Most of the time you'll only run one or two of them.

| Layer | Runner | Speed | What it covers |
|---|---|---|---|
| Rails Minitest | `bin/rails test` | ~1s | Models, request/controller, integration, mailers |
| System tests | `bin/rails test:system` | ~30s | Real headless Chrome driving the dashboard, login, password reset, full project/task/kit CRUD via the Svelte UI |
| Vitest (JS) | `bun run test:js` | ~2s | Pure Svelte component tests in `app/javascript/components/*.test.ts` |
| Transcription REPL | `script/transcription_repl.rb` | manual | Interactive harness: opens a real Chrome on the transcription tool, asserts structure of the resulting DB |

---

## Prerequisites

- **Ruby** 3.4.3 (see `.ruby-version`)
- **Bun** 1.x (`brew install oven-sh/bun/bun`)
- **Google Chrome** installed at the standard macOS path
- A working bundle: `bundle install`
- JS dependencies: `bun install`

The system and REPL tests bypass any old `chromedriver` on `PATH` and use the version-matched
driver Selenium Manager caches under `~/.cache/selenium/`. You don't need to manually update
Homebrew's `chromedriver`.

> **Run on the host, not inside Docker.** System tests and the transcription REPL harness
> both launch a real headless Chrome via `chromedriver`. Inside a container, chromedriver
> can't reach the host's Chrome and the locking-port handshake hangs (you'll see errors like
> `unable to bind to locking port 9514 within 45 seconds`). Run `bin/rails test:system`,
> `bin/repl`, and `script/transcription_auto.rb` directly on macOS — not via
> `docker compose exec web …`. The fast Minitest suite (`bin/rails test`) and Vitest
> (`bun run test:js`) don't need Chrome and run fine either inside or outside the container.

---

## Rails Minitest (`bin/rails test`)

The default test suite — fixtures, models, controllers, mailers, integration.

```bash
bin/rails test                       # whole suite
bin/rails test test/models           # one directory
bin/rails test test/controllers/passwords_controller_test.rb         # one file
bin/rails test test/controllers/passwords_controller_test.rb:25      # one test by line
bin/rails test -i "/password reset/" # by name pattern (regex)
```

What's there:
- `test/models/` — User, Project, Task, ProjectUser, TaskUser, Kit, KitType, Workflow, Tree,
  Annotation, Source, ClassDef, NodeClass, plus a fixtures smoke test.
- `test/controllers/` — Sessions, Users, Passwords, AccountActivations, Projects, Tasks,
  ProjectUsers, TaskUsers, KitTypes, Kits, Actions, JWTs, Invites, Workflows, the
  `users#show` JSON dashboard payload.
- `test/integration/project_workflow_test.rb` — end-to-end create-project → task → assign → start work → complete (server-side; bypasses the Svelte UI).
- `test/mailers/` — UserMailer, PasswordsMailer.

**Key conventions:**
- Fixtures in `test/fixtures/*.yml`. `users.yml` ERB-hashes the shared password (`password123`)
  via `BCrypt::Password.create(... cost: BCrypt::Engine::MIN_COST)`.
- `test/test_helper.rb` disables `Rack::Attack` and stubs the `vite_javascript_tag` family to
  no-ops by default (so layouts render without a Vite manifest). Both behaviors are
  toggleable for system tests.
- `sign_in_as(user)` and `sign_in_via_cookie(user)` helpers in `test/test_helper.rb`.

---

## System tests (`bin/rails test:system`)

Real browser, real Vite bundle, real Svelte. Drives the dashboard end-to-end.

```bash
bin/rails test:system
bin/rails test:system test/system/dashboard_crud_test.rb
bin/rails test:system test/system/dashboard_crud_test.rb -i "/Workflow/"
```

These tests:
- Build the Vite bundle on first run (writes to `public/vite-test/`). To force a rebuild
  manually: `RAILS_ENV=test bun run build`.
- Set `ActionController::Base.allow_forgery_protection = true` per-test (the Svelte tool's
  `getp.js` reads `<meta name="csrf-token">` and crashes if forgery protection is off).
- Resolve a Chrome driver via `selenium-manager` with `/opt/homebrew/bin` and `/usr/local/bin`
  removed from `PATH`, so a stale Homebrew chromedriver doesn't interfere.

**Test files:**
- `test/system/login_test.rb` — sign in/out, wrong password, unactivated, signup link
- `test/system/password_reset_test.rb` — request → email → set new password → sign in
- `test/system/dashboard_test.rb` — Work tab, tab navigation, Start Now link wiring
- `test/system/dashboard_crud_test.rb` — every Projects/Tasks/Kits/Members/KitTypes/Features/Workflows/Groups/Invites/Permissions operation a user can do via the UI

**Known flake:** parallel system tests occasionally surface a `Net::ReadTimeout`. Re-run the
suite. To run serially, set `PARALLEL_WORKERS=1`.

---

## Vitest (`bun run test:js`)

Svelte 5 component tests. Tests live next to the components they exercise.

```bash
bun run test:js                                # one-shot
bun run test:js:watch                          # watch mode
bun run test:js app/javascript/components/header.test.ts
```

Coverage:
- `input_text`, `input_select`, `input_checkbox` — Patch-style form components
- `audio_player` — `<audio>` mount + URL/blob src
- `header` — open/close toggle, kit info display
- `hello_world` — sample/canary
- `users_show` — dashboard wrapper

**Configuration:**
- `vitest.config.ts` — Vite + Svelte plugin, jsdom, `browser` resolve condition (Svelte 5
  needs this).
- `test/javascript/setup.ts` — `@testing-library/jest-dom` matchers.
- `test/javascript/mocks/` — module aliases for the `getp` CDN URL and the heavy
  `users.svelte` (replaced with a tiny stub to keep `users_show.svelte` tests focused).

---

## Run everything

There's no single "run all four" command; in CI you'd chain them. Locally:

```bash
bin/rails test && bin/rails test:system && bun run test:js
```

Total local time: ~35s (Rails ~1s, system ~30s, Vitest ~2s, plus Vite build on first system run).

---

## Transcription REPL — interactive test

`script/transcription_repl.rb` opens a real Chrome window with the transcription tool loaded
on a freshly-seeded kit pointing at `public/test_tone_10s.wav` (a 10-second 1 kHz sine tone).
You make annotations in the browser; on close the script dumps the kit's DB state and runs
structural assertions that ignore ids/timestamps/text-content but require the shape of
"a valid transcription."

The REPL runs in its own Rails environment (`repl`) on its own SQLite DB
(`storage/repl.sqlite3`) and its own port (`3001`) — fully isolated from dev and test, so
your normal `bin/dev` on `:3000` can keep running.

### Start the REPL server

```bash
# in terminal 1
bin/repl
```

`bin/repl` is a small wrapper that sets `RAILS_ENV=repl` + `TRANSCRIPTION_REPL=1` and
launches `bin/rails server -p 3001`. The equivalent long form:

```bash
RAILS_ENV=repl TRANSCRIPTION_REPL=1 bin/rails server -p 3001
```

- `RAILS_ENV=repl` selects the dedicated env + DB (`config/environments/repl.rb`,
  `config/database.yml#repl`, `config/vite.json#repl`).
- `TRANSCRIPTION_REPL=1` enables `config/initializers/transcription_repl_patch.rb`,
  which makes the work-page audio manifest point at the static WAV under `public/`.

### Run the REPL script

```bash
# in terminal 2
bundle exec ruby script/transcription_repl.rb
```

The script will:
1. Verify the repl server is reachable at `http://localhost:3001/up`.
2. **First run only**: detect that the `repl` DB is empty and load `db/schema.rb` into it.
3. Idempotently set up: `replannotator` user (password `password123`), `ArcTranscription`
   class_def, the necessary `NodeClass`es, `Orderly` workflow, a kit_type, project, task,
   and project/task membership.
4. Sweep all prior kits on the REPL task and create a fresh tree + kit pointing at the WAV.
5. Open Chrome, sign in, navigate to `/workflows/<task_user>/work/<workflow>`.
6. Wait until you close the browser window.
7. Dump the kit's `Annotation`s, `Node`s, `Kit`/`TaskUser` state, and `KitState` transitions.
8. Run structural checks and exit `0` on PASS / `1` on FAIL.

### What the structural checks assert

**Failures (exit 1):**
- `kit.state` is `assigned` or `done` — the workflow finished assigning
- At least one `Annotation` row was created — the JS save path actually reached the server
- At least one `SegmentListItem` node exists — you made a segment
- Each `SegmentListItem` has both `Arc` and `Text` children
- `Arc` has an annotation with `begi` or `begr` — a time was specified
- `Text` has an annotation with a non-blank `value` — something was typed

**Warnings (exit 0):**
- `Speaker` child missing on a segment
- An `NListItem` exists but its `N` child is missing
- `N` exists without a `begr` reference time

If you change what counts as "valid" for your task, edit the `check_transcription` function
in the script.

### Files involved

| File | Role |
|---|---|
| `script/transcription_repl.rb` | The interactive harness (human makes the annotations) on a plain `.wav` kit |
| `script/transcription_repl_wrapper.rb` | Interactive variant — kit source is a JSON **wrapper** with a transcript; opens with it pre-loaded |
| `script/transcription_auto.rb` | Automated variant — Selenium drives the annotations on a plain `.wav` kit |
| `script/transcription_auto_text_only.rb` | Automated variant — the `transcribe_text_only` mode: an imported graph becomes the segments and the captions, and only text may change |
| `bin/repl` | Wrapper that launches the REPL server (`RAILS_ENV=repl TRANSCRIPTION_REPL=1`, port 3001) |
| `config/initializers/transcription_repl_patch.rb` | Manifest-injection monkey-patch (gated on `TRANSCRIPTION_REPL=1`) |
| `config/environments/repl.rb` | The dedicated `repl` Rails environment |
| `config/database.yml` (`repl:` block) | `storage/repl.sqlite3` |
| `config/vite.json` (`repl:` block) | Vite output dir + port for repl mode |
| `public/test_tone_10s.wav` | Static asset served by Rails |
| `public/test_tone_10s.json` | JSON wrapper (points at the wav + the tsv below) for the wrapper script |
| `public/test_tone_10s.tsv` | Pre-populated transcript loaded by the wrapper script |
| `test/fixtures/files/test_tone_10s.wav` | Same WAV as a fixture |
| `test/fixtures/files/generate_test_tone.rb` | Reproducible WAV generator (re-run anytime) |

### JSON-wrapper variants

The kit's source is a JSON wrapper (`public/test_tone_10s.json`) that points at
the audio **and** a TSV transcript (`public/test_tone_10s.tsv`). The kit type sets
`import_transcript_auto`, so on load the tool opens the Upload Transcript dialog
with the transcript pre-parsed. The dialog offers three choices — **Add Read Only**
(reference only), **Add with Blanks** (reference + matching empty editable
segments), and **Add and Save** (persist as editable). Sibling constraints
(`import_transcript_readonly` / `_blanks` / `_save`) skip the dialog and apply one
choice directly. This exercises the front-end wrapper-loading path in
`app/javascript/work/init.js` (`get_json_wrapper`).

- **Interactive** (`transcription_repl_wrapper.rb`) — opens Chrome with the
  transcript pre-loaded (reference + empty editable segments) so you can fill it
  in, then dumps DB state on close.

There was an automated variant too. It asserted the reference arrived as
read-only *segments*, which stopped being true when the blanks import moved to
showing the reference as a caption over the blank line, and it had been failing
ever since.

```bash
# terminal 1
bin/repl
# terminal 2
bundle exec ruby script/transcription_repl_wrapper.rb
```

### Regenerating the WAV

```bash
ruby test/fixtures/files/generate_test_tone.rb
cp test/fixtures/files/test_tone_10s.wav public/test_tone_10s.wav
```

---

## Resetting databases

```bash
bin/rails db:test:prepare              # recreate the test DB from schema (no seeds)
bin/rails db:reset                     # nuke + recreate dev DB (DESTRUCTIVE)
RAILS_ENV=repl bin/rails db:schema:load # rebuild the REPL DB from schema (DESTRUCTIVE)
```

`config/ua.rb` runs at boot and re-seeds `NodeClass`/`Workflow`/`Task` from `ua.config`.
Fixture loading wipes the seeded rows — that's expected, the test fixtures have their own
canonical replacements.
