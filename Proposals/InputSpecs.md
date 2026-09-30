<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0006-input-specs

Modified: 2026-10-01

# Input specs

This proposes a clean boundary between the silo and whatever obtains the files it encodes. Some
process outside the silo — a disc ripper, a download manager, a capture card's software, a person
with a folder of files — obtains an **input mezzanine** and describes it in an **input spec**: a
description of the file's streams in a vocabulary the silo defines and no mechanism owns. The silo
derives the facts a rule tests from that description, resolves a ruleset against them, and returns
a concrete recipe. The process that produced the mezzanine may then adjust that recipe for
something particular to this one input, as the last step of its ingestion, and the silo records the
adjustment beside the decision it replaced.

The silo stops knowing how any file was obtained. MakeMKV's scan, its stream flags and the
reconciliation of its track counts leave the server for the producer that uses MakeMKV; the silo
keeps one producer of its own, for a plain file, built on the `ffprobe` it already runs.

## The problem

The silo knows how discs are ripped. Registration takes an `ffprobe` probe of the file and
`MakeMKVFacts`, MakeMKV's account of the disc title it came from
([jobs](../openspec/specs/jobs/spec.md)); assignment merges the two, applying MakeMKV's per-track
facts only when its kept-track count matches the probe's, and derives a commentary from MakeMKV's
stream flags — bits 1 and 2 — before it looks at the file's own dispositions
([recipes](../openspec/specs/recipes/spec.md)). `silo-ctl encode` takes a `--makemkv` file. The
server's types carry `MakeMKVTrack` and `ProbedStream` with `ffprobe`'s spelling of every field.

That is the ingestion tool's knowledge in the wrong place. Every other way a household gets a file —
a download, a recording, a file a friend handed over, a remux done by hand — has to arrive shaped
like a rip: a probe the silo can read, and a scan that is absent. A second disc tool, with its own
flags and its own idea of which stream is a core, would mean teaching the server a second
mechanism. And the reconciliation that exists only because MakeMKV lists tracks in its own order is
run by a server that never saw the disc.

And the recipe is the last word. The rules decide every stream, which is what they are for, but the
person ingesting a file sometimes knows something the rules cannot: that this disc's second audio
track is mislabelled, that this one film's Atmos mix should be kept whole even though the household
re-encodes TrueHD. Today the only way to say so is a rule, written into the household's ruleset,
that exists for one file.

## What this is

**1. A producer obtains a mezzanine and describes it.** Outside the silo, a producer obtains the
input mezzanine — the file to be encoded — and writes an input spec: the file's streams, each with
its codec, its shape, its language and title, and the **marks** that say what it is for, in the
silo's vocabulary. The producer translates its own mechanism's signals into that vocabulary; it
does not decide what the silo's facts are. The silo provides one producer, for a plain file; smd-tools'
ingestion app, which uses MakeMKV, is another.

**2. The silo derives facts and resolves a recipe.** Registration takes the mezzanine's file
reference and its input spec. Assignment adds what the silo's library knows — the item, its kind
and profile, the feature map — and the silo derives the facts a rule tests, in one place, then
resolves the ruleset against them. The dry-run resolve route takes the same input, so a producer can
show the recipe before it assigns anything.

**3. The producer may adjust the recipe.** As the last step of ingestion, the producer may send
adjustments with the assignment: for any stream, an action that replaces the one the rules chose,
with a note saying why. The silo applies them, checks the result is still a recipe, and records each
adjusted decision with the rule's decision it replaced.

## Principles

0001-silo's principles stand: facts are discovered and rules are written; a decision is recorded
with what it decided. This proposal adds four of its own.

1. **The silo knows descriptions, not mechanisms.** Nothing in the server knows how a file was
   obtained. A mechanism's signals are translated into the input spec's vocabulary by the producer
   that uses the mechanism, and a new mechanism is a new producer, never a change to the server.
2. **Observed by the producer, derived by the silo.** A producer says what it saw: this stream's
   codec and profile, this one's transfer characteristic, that one marked as a commentary. The silo
   draws the conclusions a rule tests — lossless, role, HDR — in one place, so every producer's
   files are judged the same way.
3. **The rules decide; the ingestion may correct, and says so.** An adjustment is a decision a
   person made about one input, recorded beside the rule's decision it replaced. The rules are not
   bent to fit one file, and the record never hides that one was overridden.
4. **One way in.** The input spec is the only description of a mezzanine the silo reads, for a job
   and for a dry run alike. There is no second path for probes, scans or pre-derived facts.

## Vocabulary

- **Input mezzanine** — the file a producer obtained and hands to the silo to be encoded. "Source
  file" in the specs until now.
- **Producer** — the process that obtains a mezzanine and writes its input spec.
- **Input spec** — the description of one mezzanine: its streams and what was observed about them,
  in the silo's vocabulary.
- **Mark** — one word in the input spec saying what a stream is for or how it is flagged:
  `default`, `forced`, `commentary`, `descriptive`, `hearingImpaired`.
- **Adjustment** — an action for one stream that replaces the one the rules chose, sent by the
  producer as the last step of ingestion.

## The input spec

```json
{
  "label": "Pyramids of Mars, disc 1, title 4",
  "medium": "dvd",
  "duration": 1497.6,
  "streams": [
    { "index": 0, "kind": "video", "codec": "mpeg2video", "width": 720, "height": 576,
      "frameRate": 25, "interlaced": true, "transfer": "bt470bg", "bitDepth": 8 },
    { "index": 1, "kind": "audio", "codec": "ac3", "channels": 2, "language": "eng",
      "marks": ["default"] },
    { "index": 2, "kind": "audio", "codec": "ac3", "channels": 2, "language": "eng",
      "title": "Commentary", "marks": ["commentary"] },
    { "index": 3, "kind": "subtitle", "codec": "dvd_subtitle", "language": "eng",
      "marks": ["forced"] }
  ],
  "notes": [{ "stream": 2, "text": "the disc marks this track as the director's comments" }]
}
```

| Field | Means | Vocabulary |
|---|---|---|
| `label` | a name for the mezzanine a person will recognise | free text |
| `medium` | the physical medium the mezzanine came from, when it came from one | `dvd`, `bluray`, `uhd` |
| `duration` | length in seconds | number |
| `streams[].index` | the stream's position among all the mezzanine's streams, from zero, as `ffmpeg` addresses it | integer, unique |
| `streams[].kind` | `video`, `audio`, `subtitle`, or `other` for a stream no rule decides (data, attachments) | closed |
| `codec`, `profile` | the codec and its profile | `ffmpeg`'s names: `truehd`, `dts` with profile `DTS-HD MA`, `hdmv_pgs_subtitle` |
| `width`, `height`, `frameRate`, `interlaced`, `bitDepth` | the video's shape | numbers; a flag |
| `transfer` | the video's transfer characteristic | `ffmpeg`'s names for ITU-T H.273's: `bt709`, `smpte2084`, `arib-std-b67` |
| `channels`, `layout` | the audio's channels | an integer; `ffmpeg`'s layout name |
| `language` | the stream's language | ISO 639-2, such as `eng` |
| `title` | the stream's title as the mezzanine carries it | free text |
| `marks` | what the stream is for or how it is flagged | `default`, `forced`, `commentary`, `descriptive`, `hearingImpaired` |
| `coreOf` | for a lossy core extracted from inside a lossless stream, that stream's `index` | an audio stream's index |
| `notes` | things the producer noticed and a person should see, optionally about one stream | free text; never a fact |

The codec, profile, transfer and layout names are `ffmpeg`'s. That is not a mechanism leaking in:
`ffmpeg` is what the silo's nodes encode with, a rule already tests `audio.codec` in those names,
and they are the one vocabulary for codecs every tool in the pipeline already speaks.

The silo refuses an input spec — 400, naming what is wrong — when a stream index repeats, a kind or
mark is not in the vocabulary, a `coreOf` names no audio stream of the spec or names itself, or a
required field is missing: `index`, `kind` and `codec` on every stream; `width` and `height` on
video; `channels` on audio.

## What the silo derives

| Fact | Derived from |
|---|---|
| `format` | the assignment's format, else the spec's `medium` |
| `duration`, codecs, sizes, frame rate, bit depth, channels, languages | the spec, as stated |
| `video.interlaced` | the spec's `interlaced`, false when absent |
| `video.hdr` | `transfer`: `smpte2084` is `hdr10`, `arib-std-b67` is `hlg`, anything else none |
| `audio.lossless` | `codec` and `profile`, by the one function every caller shares |
| `audio.role` | the assignment's feature map first; then the marks, `commentary` before `descriptive`; else `main` |
| `audio.core` | whether the stream has a `coreOf` |
| `subtitle.forced` | whether the stream is marked `forced` |

A stream titled as a commentary that nothing marks one, and a mezzanine with more than one video
stream, are hints, as they are today; the producer's `notes` join them. The first video stream is
the one described and decided.

## Producers

**The plain-file producer** is the silo's own. It runs `ffprobe` on a file, as the encoder already
does for outputs, and writes the input spec from what it reports: `field_order` other than
`progressive` is interlaced; `color_transfer` is the transfer; the `comment` disposition is the
`commentary` mark, `visual_impaired` and `descriptions` are `descriptive`, and `forced`,
`hearing_impaired` and `default` are their marks. It knows no medium and no cores. `silo-ctl encode`
uses it when it is given a file and no spec, and a script can run it through `silo-ctl` to register
a download or a recording.

**The disc producer** is smd-tools' ingestion app, which already runs MakeMKV and `ffprobe`. It
writes the spec from both: the probe for what the file holds, MakeMKV's scan for what the file did
not say. MakeMKV's flag bits 1 and 2 become `commentary`, bit 4 `descriptive`; a track MakeMKV
extracted as a lossless track's core gets `coreOf`; a forced-only stream gets `forced`; the disc
type becomes `medium`. The reconciliation of MakeMKV's track order with the file's streams, and its
refusal to apply the scan when the counts differ, move with it, and a mismatch becomes one of the
spec's `notes`. The silo sees the result and none of the mechanism. That work is smd-tools', and is
not specified here.

## Registration and assignment

`POST /v1/jobs` takes the mezzanine's file reference and its input spec, and nothing else; the
disc name becomes the spec's `label`. An input spec the silo refuses refuses the registration.

`PUT /v1/jobs/{id}/assignment` is unchanged in what it carries, adjustments aside: the library, the
lineage, the item, its alternative and profile, the feature map, the chapters, the ruleset. The
silo derives the facts from the job's input spec and the assignment, and resolves.

`POST /v1/rulesets/{name}/resolve` takes the input spec in place of pre-derived facts, with what the
assignment would add — the kind, profile and format, the role of each audio stream the feature map
names, and the feature map for renumbering — and optional adjustments, and answers the recipe an
assignment would record. It stays a dry run.

## Adjustments

An adjustment names a stream by its kind and its index from one among streams of its kind — the way
a recipe's decisions and the sidecar's `<track>` count — and gives the action to take instead:
`copy`, `drop`, or `encode` with settings exactly as a rule's `<encode>` carries them. It may carry
a note.

The silo resolves first, then applies each adjustment to the decision for its stream, then
recomputes what follows from the decisions: the layout, the renumbered feature map, the warnings,
and the encoders the recipe needs. An adjustment that names a stream the recipe has no decision for
is refused with 400; so is a second adjustment for one stream. Each adjusted decision keeps the
rule that decided it and records the action the rule chose and the adjustment's note, so reading
the job answers both "what did this stream get" and "what would the rules have given it".

Adjustments are part of the assignment, so they are made while a job is `unassigned`, `pending` or
`failed`, as an assignment is; a job re-assigned is resolved again and its new assignment's
adjustments applied. There is no route for adjusting a job afterwards: an adjustment is the
producer's last word on its input, made before a node claims it.

Where [0007-layered-rulesets](https://github.com/media-silo/silo-server/pull/47) asks which placed presentations the current rules
would make differently, an adjusted stream is the ingestion's decision and not the rules', and is
not compared; that proposal is rebased on this one to say so.

## What this looks like to the operator

A household ingests a film from disc. The ingestion app rips it, probes it, reads MakeMKV's scan,
and writes the input spec: a TrueHD Atmos track, an AC-3 track MakeMKV marks as the director's
commentary, the lossy core of the TrueHD with `coreOf` pointing at it. It asks the silo for the
recipe against the library's rules: the TrueHD becomes FLAC, the commentary AAC, the core dropped.
The person at the app knows this film's Atmos mix is the reason they bought it, and adjusts the
TrueHD stream to `copy`, noting "keep the Atmos object track". They assign. The job's recipe copies
the TrueHD, and says that `lossless-main` would have made it FLAC.

The next week they add a documentary downloaded as an MKV. A script runs `silo-ctl` to write its
input spec with the plain-file producer and registers it; the same rules decide it, and nobody
had to pretend it was a disc.

## What this asks of an implementation

Each step is a pull request, in order, and each carries its spec deltas into `openspec/` per the
corpus README — the deltas are written now, under [`specs/`](InputSpecs/specs/) beside this
proposal.

### 1. The input spec

`InputSpec` in SiloKit, with its validation; facts derived from it and an assignment, replacing the
merge of a probe and a MakeMKV scan; `MakeMKVFacts` and `MakeMKVTrack` removed, and `ProbedSource`
moved into the encoder, where the plain-file producer maps it to an input spec; registration taking
an input spec; the resolve route taking one; `silo-ctl encode --input <spec>`, with the plain-file
producer when no spec is given and `--makemkv` gone; the OpenAPI document and SiloClient to match;
an example spec under `Examples/`. The input-specs, recipes, rulesets, jobs registration and record,
read-api and encoding deltas apply here; the rulesets and recipes specs' purpose text loses its
account of the origin scan; and the new input-specs spec, which archiving creates with a placeholder
purpose, is given its own.

Tests: a spec with a repeated index, an unknown mark, a `coreOf` naming nothing, and a video stream
without a size are each refused, naming the fault; each derived fact comes from the field the table
names; the feature map outranks the marks; the plain-file producer maps each disposition to its
mark and field order to `interlaced`; a registration without a spec is 400; the resolve route
answers for a spec what an assignment records.

### 2. Adjustments

Adjustments in the assignment and the resolve request; applied after resolution, the layout,
feature map, warnings and requirements recomputed; each adjusted decision recording what it
replaced. The jobs assignment and recipes adjustment deltas apply here.

Tests: an adjustment to `copy` of a stream the rules encode copies it, drops the encoder from the
requirements when nothing else needs it, and records the rule's action and the note; an adjustment
to `drop` renumbers the layout and warns about a feature mapped to the dropped stream; an adjustment
for a stream the recipe does not have, and two for one stream, are refused; the resolve route
answers the adjusted recipe.

smd-tools' ingestion app then moves to writing input specs and offering adjustments; that is its own
change, in its own repository, once the first step has landed.

## Non-goals

- **Adjusting a job after its assignment.** The adjustment is the ingestion's last step. A change
  of mind after that is a re-assignment, made while the job is still `pending` or `failed`.
- **Adjusting the output or the layout directly.** An adjustment changes a stream's action; the
  layout, and the output container, follow from the actions and the ruleset.
- **Specifying producers other than the silo's own.** The input spec is the contract; how a disc
  producer or any other fills it is its own business.
- **Accepting probes or scans for compatibility.** Nothing has been released, and a second way in
  is what principle 4 rules out.
- **A codec vocabulary of the silo's own.** `ffmpeg`'s names are the pipeline's lingua franca, for
  the reason given above.

## Open questions

1. **Source references for other media.** A presentation's `<source>` records a disc and a playlist,
   the only natural key the sidecar has, and 0007 recognises an out-of-date presentation's origin
   being ingested again by it. A download or a recording has no such key. The input spec could carry
   one — a content hash, a URL — but the sidecar has nowhere to record it; that is smddb's to add.
2. **More marks.** The five marks are the ones some producer can already set. A producer that knows
   more — a karaoke track, a sign-language video — would want a word for it, and a rule a fact to
   test. They are added together, in the vocabulary and in the facts, when one is needed.
3. **Checking a producer's observations.** The silo trusts the spec: a producer that says a stream
   is `truehd` when the file holds AC-3 will get a recipe for TrueHD, and the node's layout check
   after the encode is what catches it. Probing the mezzanine at registration would catch it
   sooner, at the cost of the silo reaching every producer's files before it needs to.
