# The annotation data model

How a transcript is stored, projected and edited. Written for whoever is
debugging this next — the parts that surprise people are at the bottom.

## The record

`annotations` is the source of truth. Nothing else is. Every other structure in
this document is derived from it and can be rebuilt by replaying it.

An annotation is one of `new`, `add`, `change`, `delete`, `done`, `broken`,
`skip`. The two that build the tree:

    add     value = "5:SegmentListItem,6:Arc,7:Text,8:Speaker"
    change  iid = 7, value = "some words"      (or docid + begr, or begi/endi)

An `add` names a whole group at once: a list item followed by its children, each
as `iid:Name`. `NodeDerivation` (app/models/node_derivation.rb) replays the log
into nodes; it parses those pairs and stores whatever names it is given. There
is no vocabulary, no validation, no grammar table. **The client chooses the
names** — see `app/javascript/lib/ldcjs/waveform/groups.js`.

Structure is read from the shape of a group, not from its name:

    a group with an N child          a time anchor; the N carries docid + one time
    anything else                    a span between two anchors, named by its Arc
                                     child, with one label per remaining child

So `"31:CommentListItem,32:Arc,33:Comment"` needs no server change to work. Add
the entry to `groups.js`, send the messages, and it flows through the log, the
projection, the graph tables and the payload untouched.

## Two projections

Both are rebuilt from scratch, both are disposable, and they answer different
questions.

**`segments` / `sections`** (`Kit#snapshot`) — the readable transcript. Feeds
the dashboard, `/kits/all` and the TSV downloads. Closed vocabulary: it knows
`SegmentListItem` and `SectionListItem` and exports those. Groups it doesn't
recognise are collected and ignored — `nodes[node[:name]] ||= {}` in
`Kit#snapshot` is what makes that true, and removing it turns an unknown group
into a `nil[]=` that breaks the dashboard for every kit in the task.

**`graph_nodes` / `graph_arcs` / `graph_labels`** (`Kit#graph_snapshot`) — the
general one. `name` is a string column on arcs and labels; it carries anything.
`Kit#graph_projection` builds the same rows in memory without writing them.

## Graphs from elsewhere

`imported_graphs` / `imported_nodes` / `imported_arcs` / `imported_labels` hold
annotation graphs this app didn't produce — a reference transcript, an ASR
pass, a forced alignment. Same formalism (anchors, spans between them, labels
on the spans) so the two sides can be read and collated through one interface,
without the expansion the annotator side carries: no iid, no user, no task, no
`annotations` row behind each value.

That expansion records who did what. An import has no actions in it, so its
provenance is one fact about the whole file and lives on the container —
`docid`, tier `name`, `source`, `format`, `content_hash` — leaving the rows
lean enough for data that may be large. Rows reference each other by row id
rather than by an iid scoped to a parent, so the joins are indexed.

    ImportedGraph.import_tsv(docid:, name:, text:)   one document, that docid
    .import_tsv_by_document(name:, text:, resolve:)  a graph per document in the file
    .plan_tsv(text:, resolve:)                       what that would store, storing nothing
    #transcript_rows                                 flattened: beg, end, text, speaker, section
    #overlapping(beg, end)                           spans touching a stretch
    #graph_rows                                      anchors / spans / labels

A file routinely names several documents — `parse_tsv.js` ignores that column
because the client imports for the kit already open, and the reader here reads
it. `import_tsv` refuses such a file rather than flattening it: the documents
all start near zero, so they would share anchors and every query would cross
them. How a file's document ids become docids is stated per import, since a
missing or extra `.wav` isn't predictable — `Docid.verbatim`, `.template`, or
`.match(candidates)`, which compares stems (no directory, extension or channel
suffix, case-insensitive) and refuses to guess when a stem names two.

Unique on `(docid, name)`, so a re-import replaces a tier rather than adding
one, and unique on `(imported_graph_id, time)`, which is what makes anchors
*shared*: a contiguous transcript stores N+1 of them, not 2N, and tiers over
one timeline land on the same rows. Arcs also carry `beg`/`end` copies of their
anchors' times — the anchors are the identity, the copies are what the range
query reads.

    bin/rails imported:plan FILE= [TEMPLATE=|MATCH=kits]      # the mapping, before storing
    bin/rails imported:tsv  FILE= NAME= [DOCID=|TEMPLATE=|MATCH=kits]
    bin/rails imported:list / show / overlapping / graph
    bin/rails imported:clear SOURCE=  # or DOCID= / NAME=; the undo for an import

### Comments

`CommentList: [ 'Arc', 'Comment' ]` in `groups.js` — a span with one label,
gated by the `comments` constraint. No key binding: the Controls toolbar shows
or hides the panel, and the panel's own button makes a comment from the
selection (or from the active segment, when there's no selection). They live in
`cmtmap` and `transcript.comments`, rendered by `comments.svelte` under the
transcript, and written a second after the typing stops the way a segment's
text is.

Nothing filters them out of the transcript exports, because nothing has to:
`create_transcript` writes `transcript.segments`, `graph_segments` takes only
`SegmentListItem`, and `Kit#snapshot` ignores group names it doesn't know. An
export that *does* want them reads `graph_arcs` where `name = 'CommentListItem'`
with its label — nothing new to store.

Adding one needed no server change at all, which is what the vocabulary being
the client's is worth. The one existing thing it did change: `refold_graph`
used to treat every arc that wasn't a `SectionListItem` as a segment, so any
invented group turned up in the transcript. It dispatches on the name now, and
leaves what it doesn't recognise alone.

### transcribe_text_only

A kit type carrying this constraint transcribes *against* an imported graph.
On load the tool asks `POST /kits/imported`, which matches the kit's audio to a
graph by stem and returns the spans of one tier — the constraint's value names
it, and a bare flag means `reference`.

Those spans do two jobs: they're the captions above each segment, as in the
blanks import, and on a kit with nothing in it yet they're the segments too,
created once at the imported times, empty. After that the shape is fixed. The
annotator may change a segment's text and nothing else — not its times, not how
many there are, not speaker or section.

Enforced in three places, deliberately. `text_only_forbidden` in `bindings.js`
names the actions by action rather than by key, and `userf`/`suserf` drop them;
the segment list hides the affordances that would run them; and each operation
that would change the transcript's shape asks `text_only_refuses` (text_only.js)
at the function it goes through — creating a segment, splitting, merging,
deleting, moving a time, sections, speaker. That last one is the backstop, and
it holds whatever gesture, button or code path reached it. The seeding happens
before the lock goes on, through those same functions.

Per operation, not per message. It read the messages once, which reads every
message rather than every feature: `done` is a message, so closing a kit was
refused along with splitting one, and the annotator was stuck.

It's a separate path from the blanks import rather than a mode of it. That one
reads the kit's own source transcript and leaves everything editable, and it
stays as it is.

Comments are simply not one of the guarded operations: a remark about the audio
isn't the transcript's shape, so `add_comment_to_list` and a change to a
`Comment` label need no exception. Neither does closing the kit.

    bundle exec ruby script/transcription_auto_text_only.rb   # with bin/repl running

To turn it on: `bin/rails features:seed` for the Feature row, set the
constraint on the kit type, and import a graph whose document matches the kits'
audio. Deploying migrates but doesn't seed — `db:prepare` only seeds a database
it had to create — and `db:seed` would also reset the canonical Transcription
kit type's constraints, so `features:seed` is the one to run on a live
database.

Writing is batched across the whole file rather than done per document — one
upsert for the graphs, one delete per table, anchors/spans/labels inserted in
slices, ids taken from the inserts rather than read back. Seven thousand
documents import in about seven seconds; the same work per document took near
a minute, and nine tenths of that was Ruby building the same statements over
again, not the database. `remove_all` clears the same way, for the same reason
— `destroy_all` over thousands of graphs runs three deletes each.

The client doesn't read any of this yet. Read-only reference rows still live in
`vsegs` in `waveform.svelte`, re-parsed from the source TSV on every load, and
`sort_segments` merges them with the annotator's rows by time — the collation
that has no server-side counterpart yet.

## The task graph page

`GET /projects/:project_id/tasks/:id/graph` draws a whole task. `Task#graph_snapshot`
runs `Kit#graph_snapshot` over every kit in it — the same call the waveform's
Graph button makes, one kit at a time — and hands back a block per kit:
identity, then that kit's `nodes` / `arcs` / `labels` rows verbatim.
`task_graph.svelte` draws them; `task_graph_layout.js` is the part with no DOM
in it, and the part with tests.

Time across, a lane per **(arc name, label name)** pair down. Both come out of
the data's own `name` columns, so an invented group gets a lane, a colour and a
checkbox the first time one is annotated — the same bargain the graph tables
make everywhere else. Nothing on this path knows the vocabulary.

**A block is a document, not a kit.** `group_by_document` gathers the kits
annotating one recording — `source_uid`, or what the anchors say when a kit has
none — onto one set of lanes, so a task annotated twice over is drawn once
rather than twice down the page with a screenful of nothing between the passes.
A document is named by the end of its docid — `document_labels`. Real docids are
S3 keys and URLs whose first two thirds are the same for every document in the
task, and the part that tells two apart is at the end. Worked out over the whole
set rather than one at a time, because a basename alone isn't always enough:
anything that collides takes another path segment, and again, until the names
are distinct. The full docid stays as the tooltip.

The picker above the plot chooses which documents are drawn. It opens on the
**first document alone** — a task is routinely dozens of recordings, and all of
them at once is a wall of lanes. The time axis still spans the whole task, so
switching documents doesn't move the ruler under you.

The set is literally what's drawn; the empty one draws nothing and the page says
so. It used to stand for "all of them", which meant unticking the last box
ticked every other box instead, and there was no way to ask for nothing. All and
None are the buttons for the two ends.

**That merge is a drawing, not a graph.** Each kit keeps its own tree, so two
kits on one document have *colliding iids* and do not share anchors even where
their times line up exactly. Everything downstream of the merge therefore
identifies a span by `(kit_id, iid)` — the each-block key, the selection, the
packer's tie-break — and `neighbourhood` is asked of the kit's own block, never
the document. `resolve_block` stamps `kit_id` onto every row for this reason,
and `lanes_for` reads the labels already hanging off each arc rather than
looking them up by `arc_iid`, which would cross the two kits.

Decisions worth keeping:

- **Zoom is a computed x scale, not a viewBox.** A viewBox would scale the text
  with the drawing, which is backwards — zooming in should reveal more words,
  not enlarge the few already there. It also lets spans outside the window be
  dropped before they reach the markup, which is what keeps a long task drawable.
- **Spans are packed into rows over the whole recording, not over the window.**
  Packing per window makes a span jump rows as the one it overlapped scrolls off
  the left edge.
- **Nothing on the drawing listens for the wheel.** The window is moved by the
  position bar under the plot and sized by the zoom bar in the toolbar; the
  wheel belongs to the browser and scrolls the list of kits. It used to pan and
  zoom, which moved the drawing under the pointer when you were only trying to
  get down the page — and before that it `preventDefault`ed every wheel event,
  which swallowed the vertical scroll entirely.
- **The ruler is its own svg above the scroller**, not the top of the drawing —
  inside it, it scrolled away with the first kit and took the times with it. The
  position bar sits above the ruler for the same reason: at the bottom of the box
  it is a long way from the times it moves, and off the screen on a tall task.
- **It opens ten seconds wide, not fitted.** A whole task at once is a shape,
  not a transcript — at that scale a segment is a few pixels and none of the
  text fits. `INITIAL_SECONDS` in `task_graph.svelte`; Fit is one button away,
  and a recording shorter than the window shows all of itself.
- **Panning is a scrollbar, not a drag on the drawing.** A drag there fights the
  click that selects a span, and there is nowhere to grab that isn't already
  something. The thumb is as wide a share of its track as the window is of the
  task, which is the half of "where am I" that buttons and a slider can't say.
  Its width has a floor so it stays grabbable when zoomed far in, and the travel
  shrinks to match — without that the far end of the task is unreachable
  (`thumb_geometry`).
- **The zoom bar is logarithmic.** Linear, most of its length goes on the
  difference between the whole task and nearly the whole task, and the last few
  pixels cross several orders of magnitude.

The panel beside it is shut until a span is clicked — it is a third of the
window, and the drawing is what people came for. When open it draws one span's
structure: its two anchors, its Arc child,
its labels, and every other span sharing one of those anchors. That last is the
reason it exists — two spans meeting at one anchor and two spans merely abutting
at equal times draw identically on a timeline and are not the same graph.

A kit whose rows were replayed after its newest annotation is left alone —
`Kit.graph_current_by_tree` asks that of every kit at once, in four queries
rather than four per kit, and `Task#graph_snapshot` reads the stored rows for
those and replays only the rest. Sound because `annotations` is append-only:
nothing in the app updates or destroys one, so the newest annotation is the
whole of what could have changed. `?rebuild=1` — the Re-snapshot button —
replays everything regardless, and is the only load that says it is
snapshotting: an ordinary one says it is reading, because mostly that is all it
does.

The stamp that makes this work is taken **before** the replay, not from
whenever each row lands: what it has to mean is "these rows are the log as of
here". Stamped afterwards, an annotation written while the rows were being
built would date older than them and be called current for ever.

### Known: a tree with nothing to show is replayed every time

The stamp lives on the rows, so a tree that produces **no** rows has nothing to
date its last snapshot by and reads as stale on every load, for ever. Two shapes
do it:

- no `add` message at all — a kit opened and closed without annotating
- everything that was added was deleted again

Both are correct replays producing an empty graph; the check can't tell them
from a tree that has never been snapshotted. The page doesn't hide it — the
development task reports "5 re-snapshotted, 9 already current" on every load,
and those five are these.

**Cost**, and why it is left alone: a replay each, writing nothing. Four of the
five are one or two annotations; the fifth is 120. The whole task loads in about
200ms. It is bounded by `KIT_LIMIT` like everything else here.

**When it would stop being negligible**: a task where many kits are empty *and*
their logs are long — annotate-then-delete at scale, or a workflow that opens
kits far ahead of working them. The symptom is the re-snapshotted count staying
high across loads while the page gets slower. To see it anywhere:

    bin/rails runner 'Kit.where(task_id: N).each { |k| next if k.tree_id.nil?; \
      puts "#{k.id} anns=#{Annotation.where(tree_id: k.tree_id).count} current=#{k.graph_current?}" }'

**The fix if it does**: a `graph_snapshot_at` column on `trees`, set by
`Kit#graph_snapshot` to the same `as_of` the rows get. Then the stamp survives a
snapshot that writes nothing, `graph_current?` reads it instead of the max row
timestamp, and both shapes settle after one pass. It is a migration and a
schema-cache restart of `bin/repl` away (see Traps), which is why it isn't here
yet — not because the column would be wrong.

Snapshotting replays every annotation of every kit, so the request is bounded at
`TasksController::KIT_LIMIT` kits; `?limit=0` asks for the whole task. What was
left out is reported in the payload (`truncated`, `unopened`) and said on the
page — a page that quietly drew half a task would be worse than one that refused.

## Copying a task down from production

    bin/rails task:pull TASK_ID=42              # export there, import here
    bin/rails task:pull TASK_ID=42 REPLACE=1    # over a copy already here
    bin/rails task:export TASK_ID=42 > t.json   # the halves, usable alone
    bin/rails task:import FILE=t.json

`pull` runs the export through `kamal app exec`, the way kits.rake already
reaches production, and loads what comes back. `TaskTransfer` is what all three
call.

It carries what the task *is*: its project and workflow, its kit type and the
node class and class def behind that, its members, its kits, their trees, and
every annotation on them. The annotations are the record, so a copy that has
them has the task — `graph_*` and `segments`/`sections` are left out and rebuild
on demand, and the operational tables (actions, kit_stats, kit_values, versions)
aren't read to render a transcript.

Two things decide what the copy looks like:

- **Rows are copied as raw column values, not through the models.** `Task#meta`,
  `KitType#constraints` and `Kit#source` are Ruby-serialized hashes, and a model
  round trip re-encodes them; validations and callbacks fire too, and a
  re-import trips over Task's uniqueness check on name.
- **Shared rows are matched by name, the task's own rows keep their ids.**
  This database has its own project 7 and it may not be the same project, so
  projects, workflows, class defs, node classes, kit types and users are looked
  up by their natural key and only created when missing — `MERGED`, with
  `REFERENCES` listing every column that then has to be pointed at the local
  row. Kits, trees and annotations keep the ids they had, so a kit id in a bug
  report or a URL means the same thing at both ends. A task already here is a
  refusal unless `REPLACE=1`.

A person arrives with their name and no way in: a random digest, not activated,
not an admin. A real password hash is a credential, and copying one into a
development database isn't part of copying a task.

## Serving a kit

`GET /kits/get` → `Kit#to_hash(nodes_from:)`, and `payload_source` in the
response says which route ran:

    graph_memory  (default) graph_projection in memory → flattened to nodes +
                  node_values. No snapshot needed, so nothing can be stale.
    log           ?payload=log — replay the log directly, the older path
    graph         ?payload=graph_stored — read the stored graph rows back

All three produce the same tree. `bin/rails kits:payload_diff KIT_ID=n` asserts
it. The wire format is identical in every case: flat `nodes` + `node_values`,
exactly what the tool has always been sent.

## The client

    /kits/get
      → graph_from_payload.js      folds the flat payload back into
                                   { nodes: anchors, arcs: spans, labels }
      → transcript.svelte.js       the `graph` rune holds those rows
      → waveform.svelte
          refold_graph()           rows → segmap / secmap / nmap entries:
                                   creating a row when a span appears, dropping
                                   it when the span goes, and setting beg, end,
                                   docid, text, speaker, section from the graph
          sort_segments()          → transcript.segments → segments.svelte

Editing runs in one direction, and the order matters:

    add_message(n, m, v)                       modification2.js
      'add'    → ldc.allocate_group(list)      graph_write.js new_group():
                                               allocates iids off obj.last_iid,
                                               encodes the group string
               → ldc.addf(list, group)         node layer built to match
               → apply_to_graph                rows gain the span + labels
      'change' → resolve "new.Text" to an iid
               → apply_to_graph                rows updated
               → changef                       iid normalisation only
      'delete' → apply_to_graph → deletef
      then     → sort_segments()               the render pump
      then     → POST /annotations

`apply_to_graph` runs **before** the node layer, because the row values it
writes are what the transcript renders. Applying afterwards renders one message
behind.

The node layer (`ldc.nodes`, built by `init_nodes` in `app/javascript/work/other.js`)
is structure only: no values, no stores, no subscriptions, and nothing reads it
to render or to edit. It exists because `addf`/`deletef` maintain it and a few
call sites still walk it.

### And back: the reply is checked

The POST is the last step, not the first, so what the transcript shows is a
*prediction* of what the log will hold. The reply is how that prediction gets
tested. `helper2` sends back, per message, the node as the server replays it —
`derived.client_hash(node)`, built from `NodeDerivation.for_tree`, not an echo of
what arrived. So `confirm_message` in `modification2.js` is comparing the
client's guess against the server's own reading of the record:

    'change'  old_id matches the node sent, and node_value_compare agrees
    'add'     old_id matches, and every child's name matches the client's
    'delete'  nothing to compare

A disagreement means the prediction lost, and there is no automatic way back:
the log is the record and the client cannot rewrite it. So it reports through
`desync.svelte.js` and `desync_banner.svelte` tells the annotator to reload.
Four other paths end up in the same place — a reply that never came, a write the
server refused, a reply this page can't parse, and a tree locked by another
session, which means nothing being typed is landing at all.

Until this was wired up all of those were silent: a value mismatch went to
`console.error`, an `add` mismatch called a function that didn't exist and threw,
and the locked-tree case styled `#tree_locked_modal`, an element no view has
rendered since the Svelte rewrite.

## Invariants

- **`last_iid` is a high-water mark**, taken from the last `add` in the log —
  not the highest iid still present. Deleting the newest group leaves the graph's
  maximum below the last iid issued; a client trusting the maximum reissues iids
  that have been used.
- **iid arithmetic is load-bearing.** Within a group the list item is `n`, its
  Arc `n+1`, Text `n+2`, Speaker `n+3`; an anchor's N is `anchor+1`. Several call
  sites rely on this (`set_speaker` uses `h.iid + 3`, `update_node` uses
  `row.begi + 1`). `split_segment_at_cursor` predicts the next iids with
  `ldc.obj.last_iid + 1` *before* allocating them.
- **`arc_node_iid` and `arc_iid` name different nodes.** On an arc row,
  `iid` is the arc's own identity (the list item) and `arc_node_iid` is the
  group's Arc child — `iid + 1` by the layout above. A label's `arc_iid` is the
  arc's `iid`, never its `arc_node_iid`. Both spellings were `arc_iid` until
  they were told apart; `waveform.svelte`'s `arc.arc_node_iid ?? arc.iid + 1` is
  where the two still meet.
- **A reply is paired with the message it answers by position within its own
  request**, never by a counter spanning requests. `submissions[client_time]`
  holds what went out and the server replies in that order, so the pairing is
  local to one round trip and a lost request cannot shift it.

  This was a counter once — one monotonic index across every request — and the
  failure is worth knowing because it is silent and permanent. A request that
  failed had already recorded its messages as sent and would never answer them,
  so the counter fell behind by exactly that many and *stayed* behind: from then
  on, every reply was compared against the wrong message. Not a check that stops
  working, which someone would notice — a check that reports mismatches which
  aren't real, for the rest of the session. With a banner now attached to that
  report, a regression here puts an undismissable warning in front of an
  annotator whose work is fine.
- **The messages are the contract.** Any change to the client's write path should
  be checked by running the same gestures before and after and diffing the log:
  message, iid, value, docid, begr/endr, begi/endi, last_iid. That check has
  caught more than the test suites have.

## The speaker and section menus

Ctrl+S and Ctrl+[ open a list of speakers or sections, one per letter. The rows
are of two kinds and they don't have equal claim on a letter: **N is "new", R is
"replace"** — the menu's own functions, with letters people know — and the rest
are the speakers or sections in play, lettered in order as they appear.

`assign_menu_keys` (menu_keys.js) deals the second kind, stepping over anything
already in the keymap. It has to: counting a, b, c… straight through put the
fourteenth name on N and overwrote "new section" there, so the menu drew two
rows under N and the way to name a section that wasn't listed was gone. Every
letter after it was off by one too, so the row you pressed opened its
neighbour. Fourteen sections is an ordinary afternoon.

It lives in its own file because helpers.js, where `fill_speakers` calls it,
can't be imported without most of the waveform coming with it.

    bundle exec ruby script/section_menu_auto.rb   # with bin/repl running

drives the real menu with a `sections` constraint long enough to reach N, reads
back the rows it drew, and presses the letter to check it opens what it says.

## Traps

Things that cost real time here, with their symptoms.

- **A node's `value` field lags its store.** `svelte/store` queues subscriber
  callbacks when one store is set during another's notification, and a node's
  `value` is written by such a subscriber. During a burst — creating a segment is
  two anchors, an arc and its labels — it still holds the previous value. Symptom:
  a fold that reads `.value` produces a tree with no times, and nothing renders.
  Read the store with `get()`.
- **The same lag broke the section index**, which read the Name node's mirror.
  Symptom: exported transcripts missing the section, intermittently.
- **`ldc.crnt` is only set by `set_active_transcript_line_helper`**, which
  creating a segment doesn't go through. Symptom: split and merge silently do
  nothing until you click or arrow onto a row.
- **Two keymaps.** `,` `m` `d` exist in both `waveform_map.cursor` (plain keys on
  the `.keyboard` div, where they mean cursor movement) and `input_map.control`
  (modifier + key on the focused textarea, where they split/merge/delete). Driving
  the wrong one looks like nothing happening. `ctrl+d` only arms a confirm button,
  which is a sibling of the row, not inside it.
- **A selection past the end of the audio used to be refused silently**, which
  left the previous one in place — so playing the last segment played the one
  before it. Imported times rarely match the file to the millisecond and the
  discrepancy lands on the last segment. `set_current_selection` clamps to the
  duration now; a selection that *starts* past the end is still refused, and
  says so.
- **A menu that hands out letters has to skip its own.** The speaker and
  section menus reserve N and R; letters dealt to the names have to step over
  them, or the fourteenth name takes N and the menu's own function goes with it.
  See "The speaker and section menus".
- **A reload warning the annotator can't dismiss, on work that is actually
  fine**, means the reply-pairing has regressed — see the Invariants entry. The
  tell is that it appears shortly after any network hiccup and then never stops,
  on a transcript whose rows are correct. Check that `confirm_message` is being
  handed `submissions[client_time].messages[i]` and not an index from somewhere
  longer-lived.
- **The repl server caches the schema.** After a migration, `bin/repl` on :3001
  keeps serving the old columns until restarted. Symptom: "table X has no column
  named Y" from a column that plainly exists.

## Diagnosing

    bin/rails kits:payload KIT_ID=n            what the client gets
                                               PAYLOAD=memory|log|stored
    bin/rails kits:payload_summary KIT_ID=n    counts, bytes, replay anomalies
    bin/rails kits:graph KIT_ID=n              the rows (REBUILD=false to read
                                               what's stored)
    bin/rails kits:graph_summary KIT_ID=n      plus dangling arcs, orphan labels
    bin/rails kits:payload_diff KIT_ID=n       the three routes must agree
    bin/rails nodes:cost                       how much log a replay walks

In the browser: `/projects/:project_id/tasks/:id/graph` draws the whole task's
graph, and the Graph panel (header button, user 1 only) shows the rows the
transcript is rendered from — anchors, spans and labels, raw. **Rebuild**
replaces them with the server's own projection of the log.

The download is a check too. `create_transcript` flattens the graph a second
time (`graph_transcript.js`, which holds no state between reads) and refuses to
write a file when that disagrees with the live rows — so a bug in `refold_graph`
surfaces as a refused download rather than a wrong line in someone's TSV. It
compares beg, end, text and speaker; docid and section are assigned outside
either flattening and aren't covered. After **Rebuild** the check reaches
further, since the rows are then the server's replay rather than the client's
own graph.

End to end: `bundle exec ruby script/transcription_auto.rb` with `bin/repl`
running. It creates, edits, splits, merges, deletes, reloads and downloads,
then checks the log the client wrote — well-formed groups, iids issued once and
in order, no replay anomalies. Around 113 assertions. If you change the write
path, this is the thing that tells you.

## Deliberately gone

Don't reintroduce these; each was removed after checking nothing read it.

- **Per-node svelte stores and their value mirrors.** The tree's values live in
  the graph rows.
- **`xlass_def_id`.** It meant "old system vs new" and later "which tool", and
  every kit is the same class def. Tool selection is hardcoded to
  `maintranscription` at `work.js:435` and wants a `kit_type`-based replacement.
- **The jQuery-era `if(ldc.nodes)` alternatives**, which read the DOM instead of
  the node layer. Some of them called `window.pending_save_*` functions that had
  already been commented out — they would have thrown had they ever run.
- **A grammar in the payload.** The server used to send `def.classes`; the client
  owns it now.
- **`avm` and its cross-request counter**, the reply-pairing scheme described
  under Invariants. Also `save_message`, which existed only to feed it, and
  `error_in_message`, which the `add` mismatch branch called and which was
  defined nowhere — so that branch threw rather than reporting. `window.avm` was
  assigned and never read.
- **`#tree_locked_modal` and `#current_locked`.** The locked-tree reply used to
  style them; no view has rendered either since the Svelte rewrite, so the case
  was silent. It reports through `desync.svelte.js` now.
