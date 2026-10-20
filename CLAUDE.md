# Notes for Claude Code sessions

**Read [ARCHITECTURE.md](ARCHITECTURE.md) before touching the annotation tool.**
It covers how a transcript is stored (the annotation log), the two projections
built from it, how the client folds and edits it, and the traps that have cost
real debugging time — a store mirror that lags, two keymaps that share keys, iid
arithmetic that several call sites depend on.

Verifying work here:

    bundle exec ruby script/transcription_auto.rb   # needs bin/repl on :3001
    bin/rails test
    npx vitest run
    bin/rails test:system

The browser harness is the one that matters for anything touching the editor —
it drives real gestures and then checks the annotation log the client wrote.
Read its pass/fail line, not just the tail of its output.

If you change the client's write path, prove the messages didn't move: run the
same gestures with and without your change and diff the annotations
(message, iid, value, docid, begr/endr, begi/endi, last_iid). The log is the
record; everything else is rebuilt from it.

`bin/rails test:system` intermittently errors in the layout's `vite_javascript_tag`
when the suite runs slowly. It passes on a re-run and is unrelated to whatever
you changed.

## This repository is public

Nothing in it may refer to the private apps it shares code with — `wta`,
`pmacs`, `vital`, `cloudrecorder`, `ugain`. That includes documentation,
comments and commit messages, and it holds even when one of them is the actual
evidence for a claim: a reader outside the organisation has no idea what those
names are, so citing one either puzzles them or hands them an internal project
name for nothing. Make the claim on its own terms instead.

`app_comparison/bin/xpublic` does not catch this — it greps for hostnames,
buckets, AWS identities, keys and developer paths, not for sibling app names.
