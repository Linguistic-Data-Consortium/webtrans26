# Documentation system

This folder holds the project documentation as plain Markdown files. The same files are renderable two ways with no duplication:

- **On GitHub** — browse them directly in the repo. GitHub renders Markdown natively.
- **In the app** — `/documentation` lists all `.md` files in `docs/`, and `/documentation/<slug>` renders an individual file (via Redcarpet, server-side).

## Adding a doc

1. Drop a new `<NAME>.md` file into `docs/`.
2. Start it with a `# Heading` line — that becomes the title shown in the in-app sidebar and index.
3. That's it — no controller or route changes needed.

Slugs match filenames exactly (minus the `.md`). So `docs/USER_GUIDE.md` lives at `/documentation/USER_GUIDE` in the app and at `docs/USER_GUIDE.md` on GitHub.

## What's wired up

| File                                          | Role                                                               |
| --------------------------------------------- | ------------------------------------------------------------------ |
| `app/controllers/documentation_controller.rb` | Reads `docs/*.md`, validates the slug, hands HTML back to the view |
| `app/views/documentation/index.html.haml`     | List of all docs                                                   |
| `app/views/documentation/show.html.haml`      | Sidebar + rendered article                                         |
| `config/routes.rb`                            | `/documentation` and `/documentation/:slug`                        |
| `Gemfile`                                     | `gem "redcarpet"` for Markdown → HTML                              |

## Rendering details

Redcarpet is configured with GitHub-flavoured options: tables, fenced code blocks, autolinks, strikethrough, no intra-emphasis, space-after-headers, with TOC-data `id`s on headings. If you need a feature that isn't enabled (footnotes, math, etc.), tweak the renderer options in `DocumentationController#render_markdown`.
