<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0006-ingestion

Modified: 2026-10-01

# Ingestion: sources, bindings and recipes

This proposes how media enters the silo, as four things kept apart:

1. A **source** is a file as it physically is. A producer outside the silo describes it in an
   **input spec** — its streams and chapters, in a vocabulary the silo defines and no mechanism
   owns — and registers it. The silo mints its id and keeps track of where copies of it are, if
   anywhere.
2. A **binding** says what one entry of a library is made from: segments of one or more sources,
   joined in order, with the entry, its feature map and the ruleset to make it by.
3. A binding, the input specs of its sources and the ruleset resolve to **recipes** — one for each
   output the ruleset declares — which the producer may adjust, as the last step of ingestion,
   before they are committed.
4. A **job** is made from a recipe, and is only the run: claim, encode, place.

The silo stops knowing how any file was obtained, and stops folding all four of these into one job
record. It keeps one producer of its own, for a plain file, built on the `ffprobe` it already runs.

## The problem

**The silo knows how discs are ripped.** Registration takes an `ffprobe` probe of the file and
`MakeMKVFacts`, MakeMKV's account of the disc title it came from
([jobs](../openspec/specs/jobs/spec.md)); assignment merges the two, applying MakeMKV's per-track
facts only when its kept-track count matches the probe's, and derives a commentary from MakeMKV's
stream flags before it looks at the file's own dispositions
([recipes](../openspec/specs/recipes/spec.md)). `silo-ctl encode` takes a `--makemkv` file. Every
other way a household gets a file has to arrive shaped like a rip, and a second mechanism would mean
teaching the server a second set of flags.

**A job is four things at once.** One job record holds the file, what it is for, how to make it, and
the run that makes it, and each of those has a different shape:

- **One file holds several entries.** A television DVD often holds its episodes as chapters of one
  play-all title. Today that is a job per episode, each registering the same file.
- **One entry spans several files.** A long film split across two discs has nowhere to go: a job has
  one source.
- **One entry wants several presentations.** A full-quality and a mobile presentation of the same
  episode are two jobs, each assigned by hand with its own profile, though the rules for both are in
  one ruleset.
- **The recipe is the last word.** The person ingesting a file sometimes knows something the rules
  cannot — that this film's Atmos mix should be kept whole though the household re-encodes TrueHD —
  and the only way to say so is a rule written for one file.
- **Nothing outlives the run.** What the rules decided is recorded on the job, so asking what the
  rules would decide *now* — which [0007-layered-rulesets](https://github.com/media-silo/silo-server/pull/47)
  needs — means reaching into finished jobs; and whether a file could be made again depends on
  whether some job's source still has a holder, which no record answers.

## What this is

**Sources.** `POST /v1/sources` takes an input spec, an optional natural key, and optionally a copy:
a node holding the file, with the file reference it serves it by. The silo mints the source's id, or
answers the source it already has when the natural key matches one. Copies are added and removed as
nodes come to hold the file or let it go; a source may have none, and is still a source.

**Bindings.** `POST /v1/bindings` takes an entry — the library, the container lineage, the item and
its alternative — with the feature map, the chapter names, the sidecar's source reference, the
ruleset, and one or more **segments**: a source, and optionally a span of its chapters. The
segments' media, joined in order, is what the entry is made from; the silo checks that they can be
joined.

**Recipes.** Creating a binding resolves it against the ruleset once for each of the ruleset's
**outputs** — an unqualified `mkv` and a `mobile` `mp4`, say — and answers the recipes, each a
**draft**. A producer may adjust a draft: replace the action the rules chose for a stream, with a
note saying why. A recipe is **committed** when a job is made from it, and never changes after.

**Jobs.** `POST /v1/jobs` takes a draft recipe whose sources all have a copy somewhere, commits it,
and queues the job. A node claims it, is handed a copy of each segment, joins and cuts them, encodes,
and the silo places the result as the binding's entry, in the recipe's output profile.

The input spec, the facts derived from it, and the plain-file producer carry over unchanged in
substance from what this proposal first set out; they are described again below because sources are
now where they live.

## Principles

0001-silo's principles stand: facts are discovered and rules are written; a decision is recorded
with what it decided. This proposal adds five of its own.

1. **The silo knows descriptions, not mechanisms.** Nothing in the server knows how a file was
   obtained. A mechanism's signals are translated into the input spec's vocabulary by the producer
   that uses the mechanism, and a new mechanism is a new producer, never a change to the server.
2. **Observed by the producer, derived by the silo.** A producer says what it saw: a stream's codec
   and profile, its transfer characteristic, that it is marked as a commentary. The silo draws the
   conclusions a rule tests — lossless, role, HDR — in one place, so every producer's files are
   judged alike.
3. **Each thing is said once.** A file is registered once as a source, however many entries are
   made from it. An entry is bound once, however many outputs the ruleset makes of it. What the
   household makes is said once, in the ruleset, not chosen per ingestion.
4. **The rules decide; the ingestion may correct, and says so.** An adjustment is a decision a
   person made about one recipe, recorded beside the rule's decision it replaced. The rules are not
   bent to fit one file, and the record never hides that one was overridden.
5. **One way in.** The input spec is the only description of a source the silo reads. There is no
   second path for probes, scans or pre-derived facts.

## Vocabulary

- **Source** — a file as it physically is, registered once with its input spec. The silo mints its
  id. Corresponds to smddb's DiscTitle, generalised beyond discs.
- **Copy** — a node holding a source's file, and the file reference it serves it by.
- **Natural key** — an identity a producer can compute for a source without the silo — a scheme and
  a value — by which registering the same source twice finds the first.
- **Input spec** — the description of a source: its streams and chapters, and what was observed
  about them, in the silo's vocabulary.
- **Mark** — one word in an input spec saying what a stream is for or how it is flagged: `default`,
  `forced`, `commentary`, `descriptive`, `hearingImpaired`.
- **Producer** — the process that obtains a source and describes it.
- **Binding** — what one entry is made from: segments of sources, joined in order, and how the
  entry's features map to the joined streams. Corresponds to smddb's Binding, generalised to
  several segments.
- **Segment** — a source, or a span of its chapters, as one piece of a binding.
- **Output** — one presentation a ruleset makes of every entry: a profile, or none, and a
  container.
- **Recipe** — the resolved instructions for one output of one binding. A **draft** until a job is
  made from it, then **committed**.
- **Adjustment** — an action for one stream of a draft recipe that replaces the one the rules chose.
- **Job** — one run of one committed recipe: claimed, encoded and placed.

## Sources

A source is registered with its input spec, and optionally a natural key and a copy.

**The silo mints the id.** A producer cannot be relied on to identify a file the way another
producer would, and the silo cannot hash a file it does not hold, so identity is the silo's to give.

**The natural key finds duplicates.** A producer that can identify a source independently of the
silo gives a natural key: a scheme and a value, such as a disc's fingerprint and the playlist, or a
content hash, or an IMF composition's UUID. Registering a source whose natural key the silo already
has answers the existing source, with 200 rather than 201, and adds the copy if one was given; the
same key with a different input spec is 409, since one of the two descriptions is wrong. A source
without a natural key is never matched: registering the same file twice that way makes two
sources, which is the price of having no key.

**Copies are where the file is.** A copy is a node and the file reference that node serves the file
by — holder, URL, local path, size and the secret that guards it, exactly the file reference a job's
source carries today. `POST /v1/sources/{id}/copies` adds one and `DELETE` removes one, as a producer
or node comes to hold the file or lets it go. A source with no copy is kept: it is still what its
bindings were made from, and a copy can come back.

Sources are read openly, as the queue is, without their copies' secrets, which go only to a node
that claims a job needing the file; registering a source and changing its copies are the
operator's. The silo keeps each source as one JSON file under its state directory.

## The input spec

```json
{
  "format": 1,
  "label": "Pyramids of Mars, disc 1, title 4",
  "medium": "dvd",
  "duration": 5990.4,
  "chapters": [
    { "index": 1, "start": 0, "title": "Part One" },
    { "index": 2, "start": 1497.6, "title": "Part Two" },
    { "index": 3, "start": 2995.2 },
    { "index": 4, "start": 4492.8 }
  ],
  "streams": [
    { "index": 0, "kind": "video", "codec": "mpeg2video", "width": 720, "height": 576,
      "frameRate": "25/1", "interlaced": true, "transfer": "bt470bg", "bitDepth": 8 },
    { "index": 1, "kind": "audio", "codec": "ac3", "channels": 2, "language": "en",
      "marks": ["default"] },
    { "index": 2, "kind": "audio", "codec": "ac3", "channels": 2, "language": "en",
      "title": "Commentary", "marks": ["commentary"] },
    { "index": 3, "kind": "subtitle", "codec": "dvd_subtitle", "language": "en",
      "marks": ["forced"] }
  ],
  "notes": [{ "stream": 2, "text": "the disc marks this track as the director's comments" }]
}
```

| Field | Means | Vocabulary |
|---|---|---|
| `format` | the version of the input spec's shape; this proposal's is `1` | integer, required |
| `label` | a name for the source a person will recognise | free text |
| `medium` | the physical medium the source came from, when it came from one | `dvd`, `bluray`, `uhd` |
| `duration` | length in seconds | number |
| `chapters[]` | the source's chapters, in order: `index` from one, `start` in seconds, optional `title` | integers; a number; free text |
| `streams[].index` | the stream's position among all the source's streams, from zero, as `ffmpeg` addresses it | integer, unique |
| `streams[].kind` | `video`, `audio`, `subtitle`, or `other` for a stream no rule decides (data, attachments) | closed |
| `codec`, `profile` | the codec and its profile | `ffmpeg`'s names where `ffmpeg` has one: `truehd`, `dts` with profile `DTS-HD MA`, `hdmv_pgs_subtitle`; otherwise a name the producer documents |
| `width`, `height`, `interlaced`, `bitDepth` | the video's shape | integers; a flag |
| `frameRate` | frames a second, exactly | a fraction as `ffmpeg` spells it, `24000/1001`, or a whole number, `25` |
| `transfer` | the video's transfer characteristic | `ffmpeg`'s names for ITU-T H.273's: `bt709`, `smpte2084`, `arib-std-b67` |
| `channels`, `layout` | the audio's channels | an integer; `ffmpeg`'s layout name |
| `language` | the stream's language | a BCP 47 tag in its canonical form: `en`, `en-GB`, `es-419`, `zh-Hant`, `yue` |
| `title` | the stream's title as the source carries it | free text |
| `marks` | what the stream is for or how it is flagged | `default`, `forced`, `commentary`, `descriptive`, `hearingImpaired` |
| `coreOf` | for a lossy core extracted from inside a lossless stream, that stream's `index` | an audio stream's index |
| `notes` | things the producer noticed and a person should see, optionally about one stream | free text; never a fact |

The codec, profile, transfer and layout names are `ffmpeg`'s. That is not a mechanism leaking in:
`ffmpeg` is what the silo's nodes encode with, a rule already tests `audio.codec` in those names,
and they are the one vocabulary for codecs every tool in the pipeline already speaks. A codec
`ffmpeg` has no name for — an immersive audio format such as IAB, say — is named as its producer
documents it; the silo accepts it, a rule can test it, and it is not lossless, since the one function
that decides losslessness does not know it.

A frame rate is a fraction because a decimal cannot hold 24000/1001 exactly, and the fraction is
still `ffmpeg`'s spelling: it is what `ffprobe` reports.

A language is a BCP 47 tag (RFC 5646), because a language alone is not always enough to tell two
streams apart: a disc carries a Latin American and a Castilian Spanish dub (`es-419`, `es-ES`), or
Brazilian and European Portuguese, or subtitles in Traditional and Simplified Chinese (`zh-Hant`,
`zh-Hans`), and a rule may need to keep one and drop the other. The tag is in its canonical form:
the shortest ISO 639 code for the language — `en`, never `eng` — with a script in title case and a
region in capitals. A producer whose source writes an ISO 639-2 code converts it, `eng` and `fre`
or `fra` to `en` and `fr`; a language with no two-letter code keeps its three letters, as BCP 47
does. Matroska carries BCP 47 tags of its own, and `ffprobe` reports them as written, so a producer
reading one passes it on in canonical form. An unknown language is no tag at all, not `und`.

Chapters are what physically divides the source, and a binding's segments are spans of them.

**The shape is versioned, and strict.** An input spec carries `format`, and the silo reads format
`1`. A spec of a higher format is refused as newer than this silo, and a field the silo does not
know is refused, not ignored: ignoring one would turn a misspelt `intelaced` into video that is not
interlaced, the silent default this project has already had to undo in the ruleset reader. A newer
producer meeting an older silo therefore fails at registration, told which format it wrote and
which the silo reads. Adding a field or a mark is a new format; a silo reads every format up to its
own.

The silo refuses an input spec — 400, naming what is wrong — when its `format` is missing or newer
than the silo's; a field is not in the vocabulary; a stream index or chapter index repeats, or the
chapters are not in order; a kind or mark is not in the vocabulary; a frame rate is not a fraction
or a whole number; a `coreOf` names no audio stream of the spec or names itself; or a required field
is missing: `index`, `kind` and `codec` on every stream; `width` and `height` on video; `channels`
on audio; `index` and `start` on a chapter.

## Bindings

A binding says what one entry is made from and how. It carries:

- **the entry**: the library, the item's container lineage as repository documents, the item, and
  its alternative — what an assignment carries today;
- **the feature map**, mapping the container's features to streams of the joined segments, by kind
  and index from one among streams of the kind; the **chapter names** the presentation will carry;
  and the **source reference** the sidecar records on the presentation, when there is one;
- **the ruleset**, by name and optionally version, and optionally **which of its outputs** to make,
  by profile — every output when left out;
- **the segments**, one or more, each a source and optionally a span of its chapters, `from` and `to`
  inclusive.

**Segments are joined in order.** The binding's media is its segments' spans, end to end, the way
`ffmpeg`'s concat demuxer presents them, so a stream's index means the same in every segment and in
the result. That requires the segments to share a stream layout: the same streams, of the same kinds
and codecs, in the same order. A binding whose segments do not is refused. The derived facts are
the first segment's, with the duration the joined spans'.

**Spans are chapters, for now.** A span names chapters rather than times. Chapter points are where a
source divides itself — on a disc, where the authoring put episode boundaries — and they usually fall
on keyframes, which matters because a stream the recipe copies can only be cut where a keyframe is
without re-encoding it. A span in seconds, which would land mid-GOP, would force the question of
re-encoding copied streams; it is left to the proposal that needs one.

**A binding is refused** — 400, naming why — when its library is unknown, a container document
cannot be read, the item is not in the last container, the alternative is not the container's, the
feature map names a feature the container does not have or a stream the joined layout does not
have, a source is unknown, a span names chapters its source does not have or runs backwards, the
segments' layouts differ, the ruleset or its version does not exist, or an output it names is not
the ruleset's. A binding is not changed once made: a correction is a new binding.

## Outputs in the ruleset

The ruleset's `<output>` element, which today names one container, becomes a list of what the
household makes of every entry:

```xml
<output container="mkv"/>
<output profile="mobile" container="mp4"/>
```

Each output is resolved separately, with the `profile` fact set to its profile, so a rule written
for `profile is mobile` applies to the mobile recipe and no other. A ruleset with no `<output>`
makes one unqualified `mkv`, as today. Two outputs with the same profile, or two without one, are
refused. Layering, in 0007, takes the outputs from the library's ruleset alone, as it already does
the output policy.

## Recipes

**A binding resolves to its recipes when it is made.** For each output it makes, the silo derives the
facts from the segments' input specs, the binding and the output's profile, resolves the ruleset
against them, and stores the recipe as a draft. The binding's answer carries them. If any output's
resolution fails — a stream no rule decides — the binding is refused with 422 and nothing is stored,
since a binding that cannot be made is not worth keeping.

| Fact | Derived from |
|---|---|
| `kind` | the item, from the lineage |
| `profile` | the output |
| `format` | the first segment's `medium` |
| `duration` | the joined spans |
| codecs, sizes, bit depth, channels | the first segment's input spec, as stated |
| `language`, `script`, `region` | the language tag's primary language, script and region subtags, each absent when the tag has none |
| `video.frameRate` | the spec's fraction, as a number |
| `video.interlaced` | the spec's `interlaced`, false when absent |
| `video.hdr` | `transfer`: `smpte2084` is `hdr10`, `arib-std-b67` is `hlg`, anything else none |
| `audio.lossless` | `codec` and `profile`, by the one function every caller shares; false for a codec it does not know |
| `audio.role` | the binding's feature map first; then the marks, `commentary` before `descriptive`; else `main` |
| `audio.core` | whether the stream has a `coreOf` |
| `subtitle.forced` | whether the stream is marked `forced` |

A stream titled as a commentary that nothing marks one, and a source with more than one video
stream, are hints, as they are today; the producer's `notes` join them.

**A draft may be adjusted.** `PUT /v1/recipes/{id}/adjustments` replaces a draft's adjustments.
Each names a stream by kind and index from one among its kind, and gives the action to take instead
— `copy`, `drop`, or `encode` with settings exactly as a rule's `<encode>` carries them — and may
carry a note. The silo applies them to the resolved decisions and recomputes what follows: the
layout, the renumbered feature map, the warnings and the encoders the recipe needs. Each adjusted
decision keeps the rule that decided it and records the action the rule chose and the note. An
adjustment naming a stream the recipe has no decision for, or two for one stream, is refused; so is
any adjustment to a committed recipe.

**A recipe is committed once.** Making a job from a recipe commits it, and a committed recipe never
changes: it is what the job ran, and what the presentation was made by. A draft no job has been
made from may be discarded.

**A binding can be resolved again.** `POST /v1/bindings/{id}/recipes` resolves the binding against
its ruleset as it now stands and adds new drafts, one per output, leaving every earlier recipe as it
was. It is how a change of rules reaches an entry already bound, and it is what 0007's question —
what would the rules make of this now — becomes.

**The dry run** stays. `POST /v1/rulesets/{name}/resolve` takes one or more input specs, joined as a
binding's segments are, and what a binding would add — the kind, the roles the feature map gives,
and the feature map for renumbering — and answers a recipe for each of the ruleset's
outputs, storing nothing. It is for a client with no binding to resolve: a console showing a draft
ruleset, or `silo-ctl encode`.

## Jobs

**A job is made from a draft recipe.** `POST /v1/jobs` with a recipe's id commits the recipe and
queues the job `pending`, its requirements the recipe's encoders. It is refused with 409 when the
recipe is already committed, and when any of its binding's sources has no copy, since no node could
fetch it. There is no `unassigned` state any more: a job is born with everything it needs.

**A claim carries the segments.** A node claiming a job is handed, for each segment in order, a copy
of its source — its own, when it holds one — and the span in seconds, from the start of the span's
first chapter to the start of the chapter after its last, or the source's end. A claim prefers a job
whose every segment the claimant holds a copy of, then the oldest.

**The node joins and cuts.** One whole segment is encoded as today. Several, or a span of one, are
given to `ffmpeg` as one concat input, each segment's file with its in and out points, so the encode
sees the joined media the input specs describe.

**Placement** builds the presentation from the binding — the item, the alternative, the chapter
names, the feature map renumbered by the recipe's layout, the source reference — in the recipe's
output profile, and is otherwise as today.

## What changes for 0007

[0007-layered-rulesets](https://github.com/media-silo/silo-server/pull/47) is rebased on this. Its
provenance becomes the committed recipe, which already records its ruleset version; its question of
what the rules would make of an entry now becomes resolving the binding again; an adjusted stream
is the ingestion's decision and is not compared; and whether an out-of-date presentation can be
made again becomes whether its binding's sources have copies — with a re-registered source found by
its natural key rather than matched against the sidecar afterwards.

## What this asks of an implementation

Each step is a pull request, in order, and each carries its spec deltas into `openspec/` per the
corpus README — the deltas are written now, one change for each step under
[`openspec/changes/`](../openspec/changes/): `ingestion-1-sources`, `ingestion-2-outputs`,
`ingestion-3-bindings-and-recipes` and `ingestion-4-jobs-from-recipes`, each applied by its step's
pull request with `openspec archive`. The new input-specs, sources and bindings specs, which archiving creates with placeholder
purposes, are each given their own when they are applied; the rulesets and recipes specs' purpose
text loses its account of the origin scan, and the jobs spec's its account of an assignment.

### 1. Sources and input specs

`InputSpec` in SiloKit, with its validation; the sources store and routes, with natural keys and
copies; language tags checked and kept in canonical form; the plain-file producer, with an ISO
639-2 to BCP 47 table for the codes `ffprobe` reports, and the probe keeping exact frame rates and
reading chapters. The `ingestion-1-sources` change applies here. `ProbedSource` and `MakeMKVFacts`
stay where they are for now: registration and assignment still take them until step 4 removes those
routes, and they go with them.

Tests: each refusal of the input spec, naming its fault; a newer format refused; a misspelt field
refused; a natural key matched with 200 and its copy added, and refused with 409 when the specs
differ; a source with no copies kept; the plain-file producer mapping dispositions to marks, field
order to `interlaced`, `eng` and `fra` to `en` and `fr`, `und` to no language, and keeping a BCP 47
tag it is given, `ffprobe`'s fraction and chapters; a language tag that is not BCP 47, or not in
canonical form, refused.

### 2. Outputs

The ruleset's outputs, each with its profile. The `ingestion-2-outputs` change applies here. Until
bindings arrive in step 3, a resolution makes the one output its profile names, falling back to the
unqualified output so that a ruleset written with one output serves every profile it served before;
step 3's change replaces that with one resolution for every output.

Tests: a ruleset of two outputs reads as two; none reads as one unqualified `mkv`; two outputs of one
profile, and two unqualified, are refused.

### 3. Bindings and recipes

The bindings store and routes; facts derived from segments, binding and output; draft recipes, one
per output; adjustments; committing; resolving again; the dry run taking input specs; `silo-ctl
encode --input`, with the plain-file producer when no spec is given, `--profile` to pick the output,
and `--makemkv` gone. The `ingestion-3-bindings-and-recipes` change applies here. The requirements
that describe merging a probe with a MakeMKV scan, and the feature map as the assignment's, stay
until step 4: assignment still does both until that step removes it, so their removal and rewording
travel in step 4's change. A recipe is committed only when a job is made from it, so this step
builds committing into the recipe store and the fourth step calls it.

Tests: each refusal of a binding; segments of different layouts refused; a binding resolving to one
draft per output, the mobile one with `profile` set; a stream no rule decides refusing the binding
and storing nothing; each derived fact from the field the table names, `es-419` giving the
language `es` and the region `419`, and `zh-Hant` the language `zh` and the script `Hant`; an adjustment recorded with
what it replaced and the encoders recomputed; an adjustment to a committed recipe refused;
resolving again adding drafts and leaving the rest.

### 4. Jobs from recipes

Jobs made from recipes; the claim carrying segments and spans; the node joining and cutting with one
concat input; placement from the binding; registration and assignment routes removed, with the
`unassigned` state, and with them `MakeMKVFacts` and `MakeMKVTrack`, and `ProbedSource` moved into
the encoder, where the plain-file producer is its last user. The jobs, worker and encoding concat deltas apply here; a producer that used the registration and
assignment routes moves to the new ones in a change of its own.

Tests: a job from a draft commits it; a second job from it is 409; a recipe whose source has no copy
is 409; a claim carries each segment's copy and span, the claimant's own copy first; a play-all
title's middle chapters are encoded as one episode; two sources are encoded as one film; placement
writes the binding's entry in the output's profile.

## Non-goals

- **Spans in seconds.** Chapter spans only, for the reason given under Bindings.
- **Adjusting a committed recipe.** Once a job has run it, it is the record. A different decision is
  a new draft from resolving the binding again.
- **Changing or deleting bindings and sources.** A correction is a new binding; how long the silo
  keeps sources, bindings and recipes nothing refers to any more is for when there are enough of
  them to matter.
- **Specifying producers other than the silo's own.** The input spec is the contract; how any other
  producer fills it is its own business.
- **Accepting probes or scans for compatibility.** Nothing has been released, and a second way in is
  what principle 5 rules out.
- **An IMF composition playlist as the input spec.** A composition describes how to assemble a
  timeline from track files, with codec properties as SMPTE descriptors; every producer would have
  to write one to say that a stream is an AC-3 commentary, and it has no place for `coreOf` or for
  `ffmpeg`'s stream numbers. An IMF package is a binding of several sources here, and what IMF offers
  this proposal is words, which the language tags above and open question 2 take.
- **A codec vocabulary of the silo's own.** `ffmpeg`'s names are the pipeline's lingua franca.

## Open questions

1. **The sidecar's source reference.** A presentation's `<source>` records a disc and a playlist,
   the only natural key the sidecar has, and the binding passes it through. Natural keys now have a
   scheme — a disc title, a content hash, an IMF composition's UUID, an EIDR identifier — and the
   sidecar could record one in the same shape, which would let a library name where any presentation
   came from. That is smddb's to add, and the binding would then derive it from its sources rather
   than carry it.
2. **More marks.** The five marks are the ones some producer can already set. More are added as a new
   input-spec format, with the facts a rule tests for them. One gap already matters: an unmarked
   music-and-effects track takes the role `main`. IMF's audio types — primary, music and effects,
   visually impaired narration, hearing impaired, commentary, karaoke — and its subtitle types —
   forced narrative, captions for the hearing impaired, commentary, karaoke — are a ready source.
3. **Checking a producer's observations.** The silo trusts the spec; the node's layout check after
   the encode is what catches a wrong one. Probing a source when a copy is registered would catch it
   sooner, at the cost of the silo reaching every producer's files before it needs to.
4. **smddb's side.** smddb's DiscTitle is a source and its Binding a binding of one segment. Renaming
   the one and generalising the other to segments is a matching amendment there, written once this
   model has settled here.
