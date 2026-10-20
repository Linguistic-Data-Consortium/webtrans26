# webtrans26

Rails 8 application with a Svelte-based waveform transcription/annotation
front end. Runs in Docker.

## Quick start

```sh
docker compose build
docker compose up
```

The web container starts on http://localhost:3000 and the Vite dev server
on http://localhost:3036.

## Deploying

That quick start is for working on the app locally. To put it on a server, see
[Deployment](docs/DEPLOYMENT.md).

## Documentation

Project documentation lives in [`docs/`](docs/) as plain Markdown. GitHub
renders the files directly; the same files are also browsable inside the
app at `/documentation`.

[`ARCHITECTURE.md`](ARCHITECTURE.md) describes the annotation data model —
how a transcript is stored, projected and edited. It's developer-facing, so it
sits at the root rather than in `docs/`, which is what the app renders for
users.

- [Getting started](docs/GETTING_STARTED.md) — sign in, create a project
  and task, add a user, attach a demo audio kit, and start transcribing
- [Deployment](docs/DEPLOYMENT.md) — what a deployment machine needs, choosing
  a `config/deploy.yml`, secrets, SSL, persistence, and the first Kamal deploy
- [Input formats](docs/INPUT_FORMATS.md) — the two kinds of source you can
  give a kit: a plain audio file, or a JSON wrapper that also carries a
  transcript (with the wrapper schema and transcript file formats)
- [Configuration](docs/CONFIGURATION.md) — env vars, the activation flow,
  where each piece of config lives
- [Page-level keybindings](docs/KEYBINDINGS.md) — `f` / `h` / `d` / `s`,
  hint mode, and how to add per-page shortcuts
- [Documentation system](docs/DOCUMENTATION.md) — how docs are wired up,
  how to add a new one
- [Waveform editor user guide](docs/USER_GUIDE.md) — the in-app
  transcription editor

To add a new doc, drop a `<NAME>.md` file in `docs/` (start it with a
`# Heading` line for the title) and it'll appear in both views
automatically.

## License

Copyright (C) 2026 The Trustees of the University of Pennsylvania

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see <https://www.gnu.org/licenses/>. The full text is in
[LICENSE](LICENSE).
