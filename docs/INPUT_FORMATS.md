# Input formats — audio file vs. JSON wrapper

When you create a kit you give the tool a **source**: a path or URL on its own
line (see [Getting started](GETTING_STARTED.md#5-create-a-kit-from-the-demo-audio-url)).
That source can be one of two things.

## 1. A plain audio file

Point straight at the audio and the editor opens with an empty transcript.

```
https://ldcresearch.s3.us-east-1.amazonaws.com/CarrieFisher.wav
s3://my-bucket/interviews/session01.wav
```

- `http(s)://…` URLs are used as-is.
- `s3://bucket/key` paths are turned into signed URLs at load time (AWS
  credentials come from Cognito).
- The waveform only renders for a `.wav` source. Other audio (e.g. `.flac`)
  is resolved but not yet displayed.

## 2. A JSON wrapper

Point at a `.json` file instead and it acts as a manifest: it names the audio
**and** an existing transcript, so the editor opens pre-populated. This is the
way to review or correct a transcript rather than start from scratch.

The source is detected as a wrapper simply because its key ends in `.json`.
It's fetched, then its fields are resolved.

### Schema

```jsonc
{
  // --- audio: provide one of these ---
  "wav": "s3://my-bucket/interviews/session01.wav",
  "channels": [                       // OR: multi-channel audio, one path per channel
    "s3://my-bucket/interviews/session01_A.wav",
    "s3://my-bucket/interviews/session01_B.wav"
  ],

  // --- transcript: provide at most one of these ---
  "tsv": "s3://my-bucket/interviews/session01.tsv",
  "tdf": "s3://my-bucket/interviews/session01.tdf",
  "sad_with_aws": "s3://my-bucket/interviews/session01.sad.json"
}
```

| Field          | Purpose                                                            |
| -------------- | ----------------------------------------------------------------- |
| `wav`          | Single audio file to transcribe against.                          |
| `channels`     | Array of audio files (stereo / multi-channel); channel 0 is `wav`. |
| `tsv`          | Transcript in TSV format (below).                                 |
| `tdf`          | Transcript in TDF format (below).                                 |
| `sad_with_aws` | Speech-activity segments in the AWS SAD JSON format (below).      |

Every path (`wav`, `channels`, and the transcript files) is resolved the same
way as a plain source: `s3://` paths are signed, `http(s)://` are used as-is.

### How the transcript loads

When the editor opens, the **Upload Transcript** dialog offers three choices for
the parsed transcript:

| Button | Result |
| ------ | ------ |
| **Add Read Only** | Loads the transcript as read-only reference segments (view-only; not saved). |
| **Add with Blanks** | Empty editable segments at the reference times, with the reference text shown as a caption **above** each segment whose time span **overlaps** it — so annotators see what was said and type the true transcript into the blank below it, and the caption stays put even if they nudge the segment's extent. No separate read-only rows are added. |
| **Add and Save** | Persists the transcript as normal editable segments (annotations). |

A set of task constraints controls whether the dialog appears and, if not, which
choice is applied automatically on load:

| Constraint | Behavior |
| ---------- | -------- |
| `import_transcript_auto` | Opens the dialog and lets the annotator pick. |
| `import_transcript_readonly` | Skips the dialog → **Add Read Only**. |
| `import_transcript_blanks` | Skips the dialog → **Add with Blanks**. |
| `import_transcript_save` | Skips the dialog → **Add and Save**. |

With none of these set, open the dialog yourself from the editor toolbar (it also
lets you upload a local TSV / TDF / JSON file by hand). Note: automatic loading
currently wires up the **TSV** transcript format only.

## Transcript file formats

All three carry the same result — a list of segments with a start time, end
time, text, and (optionally) speaker and section.

### TSV (tab-separated)

One segment per line, in either of two column layouts. The layout is taken from
the header row when there is one; otherwise it's inferred from which columns
hold the times.

**Kit style** — header row starting with `Kit`:

| Col | 0   | 1   | 2       | 3       | 4    | 5       | 6       |
| --- | --- | --- | ------- | ------- | ---- | ------- | ------- |
|     | `Kit` | `Source` | `Begin` (s) | `End` (s) | `Text` | `Speaker` | `Section` |

**File style** — header row starting with `file`:

| Col | 0   | 1   | 2   | 3    | 4       | 5       |
| --- | --- | --- | --- | ---- | ------- | ------- |
|     | `file` | `beg` (s) | `end` (s) | `text` | `speaker` | `section` |

In either style the trailing **speaker** and **section** columns may be omitted
(they come back as empty strings), and the header row itself may be omitted.
Rows whose begin/end columns aren't numbers are skipped.

### TDF (tab-separated)

One segment per line. Lines whose first column contains `;` are comments and
are ignored. Columns:

| Col | 0   | 1   | 2       | 3       | 4       | 5   | 6   | 7    |
| --- | --- | --- | ------- | ------- | ------- | --- | --- | ---- |
|     | —   | —   | `beg` (s) | `end` (s) | speaker | —   | —   | text |

### AWS SAD JSON (`sad_with_aws`)

A JSON array of `[beg, end, label, text]` tuples. Entries whose `label` is
`nonspeech` are dropped; the rest become segments (no speaker or section).

```json
[
  [0.0,  3.42, "speech",    "hello there"],
  [3.42, 4.10, "nonspeech", ""],
  [4.10, 7.88, "speech",    "how are you"]
]
```
