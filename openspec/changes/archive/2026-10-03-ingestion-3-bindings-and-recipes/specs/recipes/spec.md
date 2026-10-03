<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: Losslessness, role and core-ness are each derived in one place

`AudioFacts.isLossless` SHALL be a function of codec and profile only, so that a producer, the
resolver and the node at encode time agree: TrueHD, MLP, FLAC, ALAC, WavPack, TTA, APE and any
`pcm_` codec are lossless, DTS is lossless only when its profile is DTS-HD Master Audio (the DTS-HD
High Resolution profile is not), and anything else is not — including a codec `ffmpeg` has no name
for, which its producer has named.

`AudioRole` SHALL be derived from the sources in order of authority: the binding's feature map
first, then the stream's marks in the input spec — `commentary` is commentary, and failing that
`descriptive` is descriptive. When neither speaks the role is `main`. A stream title that merely
says "commentary" SHALL NOT set the role; it is reported as a hint instead. The `core` fact — the
lossy core inside a lossless track, the same audio again, smaller and worse — SHALL be true exactly
for a stream the input spec gives a `coreOf`.

#### Scenario: dts is lossless only as Master Audio
- **WHEN** `isLossless` is called for `("dts", "DTS-HD MA")`, `("dts", "DTS-HD HRA")`, `("pcm_s24le", nil)` and `("ac3", nil)`
- **THEN** the answers are true, false, true and false

#### Scenario: the feature map outranks the marks
- **WHEN** a binding maps a stream to isolated music while the input spec marks it `commentary`
- **THEN** the role is `isolatedMusic`

#### Scenario: nothing speaks
- **WHEN** no feature is mapped to the stream and the input spec marks it only `default`
- **THEN** the role is `main`

Pinned by: `Tests/SiloKitTests/FactsTests.swift` (`losslessIsAFunctionOfCodecAndProfile`); the role
from marks is pinned by nothing yet.

### Requirement: Facts are derived once from a binding, its sources and an output
`SourceFacts` SHALL be derived, in one place, from a binding, the input spec of its first segment's
source, and one output of its ruleset. `kind` SHALL be the item's, from the lineage; `profile` SHALL
be the output's; `format` SHALL be the first segment's `medium`; `duration` SHALL be the joined
spans' length; and an audio stream a feature is mapped to SHALL take its role from that feature —
`commentary` for a commentary, `isolatedMusic` for isolated music, `other` otherwise. The first video
stream SHALL be described and further video streams reported as a hint. Each stream's codec, size,
bit depth, channels and title SHALL be the spec's; an audio or subtitle stream's `language`,
`script` and `region` SHALL be its language tag's primary language, script and region subtags, each
absent when the tag has none or the stream has no tag; `video.frameRate` SHALL be the spec's
fraction as a number, its numerator divided by its denominator; `video.interlaced` SHALL be the
spec's `interlaced`, false when absent; `video.hdr` SHALL be `hdr10` for a `transfer` of
`smpte2084`, `hlg` for `arib-std-b67`, and absent otherwise; `subtitle.forced` SHALL be whether the
stream is marked `forced`. Streams of kind `other` SHALL be neither described nor decided. The
specs' notes SHALL join the hints the derivation raises. Audio and subtitle streams SHALL be numbered
from one among the streams of their kind — the way a player's menu counts and the way the sidecar's
`<track audio="n">` counts — while each keeps the spec's `index` as its `absoluteIndex`.

#### Scenario: HDR from the transfer characteristic
- **WHEN** a source's video stream has `transfer` `smpte2084`, and another's has `bt709`
- **THEN** the first's `video.hdr` is `hdr10` and the second's is absent

#### Scenario: a language tag split into its parts
- **WHEN** one audio stream's language is `es-419` and a subtitle stream's is `zh-Hant`
- **THEN** the audio's `language` is `es` and its `region` `419`, with no `script`; the subtitle's
  `language` is `zh` and its `script` `Hant`, with no `region`

#### Scenario: a fractional frame rate
- **WHEN** a source's video stream has `frameRate` `24000/1001`
- **THEN** the `video.frameRate` fact is 24000 divided by 1001, and a rule testing
  `<when fact="video.frameRate" lt="24"/>` holds for it

#### Scenario: a title that says commentary is a hint, not a role
- **WHEN** an audio stream at index 3 is titled "Commentary with the director" and nothing marks it
- **THEN** its role stays `main` and a hint on stream 3 reads: titled "Commentary with the director" but nothing marks it a commentary; assign it to a feature if it is one

#### Scenario: an episode's duration
- **WHEN** a binding spans chapter 2 of a source whose chapters start at 0, 1497.6 and 2995.2 seconds
- **THEN** the `duration` fact is 1497.6

Pinned by: nothing yet.

### Requirement: A binding resolves to one draft recipe for each output
Making a binding SHALL resolve it once for each output it makes — every output of its ruleset, or
those its profiles name — deriving the facts for that output and resolving the ruleset's rules
against them, and SHALL store each recipe as a `draft`, naming its binding, its output, and the
ruleset version resolved. If any output's resolution fails because a stream no rule decides, the
binding SHALL be refused with 422 carrying the resolver's report, and nothing stored. The binding's
answer SHALL carry its recipes. `GET /v1/recipes/{id}` SHALL answer one recipe, with no token
asked, or 404 for an id the silo does not know.

#### Scenario: two outputs, two recipes
- **WHEN** a binding is made against a ruleset whose outputs are an unqualified `mkv` and a `mobile`
  `mp4`, and whose video rules are one scaling to 720 lines when `profile` is `mobile`, then a
  condition-less copy
- **THEN** it has two draft recipes; the mobile one scales the video and the unqualified one copies
  it

#### Scenario: an output no rule can make
- **WHEN** a binding's ruleset has a mobile output but no audio rule that holds when `profile` is
  `mobile`
- **THEN** the binding is refused with 422, naming the undecided audio stream, and nothing is stored

Pinned by: nothing yet.

### Requirement: An adjustment replaces a draft's decision and is recorded with what it replaced
`PUT /v1/recipes/{id}/adjustments`, behind the operator's token, SHALL replace a draft recipe's
adjustments with those given and answer the recipe. An adjustment SHALL name a stream by kind and by
its index from one among streams of its kind, give an action — `copy`, `drop`, or `encode` with the
settings a rule's `<encode>` carries — and optionally a note. Adjustments SHALL be applied to the
decisions the ruleset made: each replaces the action of its stream's decision, which SHALL keep the
rule that decided it and record the action the rule chose and the note. The layout, the renumbered
feature map, the warnings and the encoders the recipe needs SHALL then follow from the adjusted
decisions. An adjustment naming a stream the recipe has no decision for, or a second for one
stream, SHALL be 400 naming it; any adjustment to a committed recipe SHALL be 409. An empty set
SHALL restore the decisions the ruleset made.

#### Scenario: a stream kept that the rules would encode
- **WHEN** `lossless-main` encodes audio 1 as FLAC in a draft, and its adjustments are set to give
  audio 1 `copy` with the note "keep the Atmos object track"
- **THEN** the recipe copies audio 1, its decision still names `lossless-main` and records that the
  rule chose FLAC and the note, and `flac` leaves the recipe's encoders when no other stream needs it

#### Scenario: a stream dropped renumbers the rest
- **WHEN** an adjustment drops audio 2 of three, and a feature is mapped to audio 2
- **THEN** the layout holds the source's audio 1 and 3 as output audio 1 and 2, and the recipe warns
  that the feature is mapped to a stream this recipe drops

#### Scenario: a committed recipe is not adjusted
- **WHEN** adjustments are put to a recipe a job has been made from
- **THEN** the answer is 409, and the recipe is as it was

Pinned by: nothing yet.

### Requirement: A recipe is committed once, and never changes after
Making a job from a draft recipe SHALL commit it, and a committed recipe SHALL NOT change: neither
its decisions, its adjustments nor its ruleset version. `DELETE /v1/recipes/{id}`, behind the
operator's token, SHALL discard a draft and SHALL be 409 for a committed recipe.

#### Scenario: a draft discarded
- **WHEN** the operator discards a draft no job was made from
- **THEN** the recipe is gone, and its binding's other recipes are as they were

Pinned by: nothing yet.

### Requirement: A binding can be resolved again, leaving its earlier recipes as they were
`POST /v1/bindings/{id}/recipes`, behind the operator's token, SHALL resolve the binding against its
ruleset as it now stands — the latest version, unless the binding names one — and store a new draft
for each output it makes, answering them. Every recipe the binding already had SHALL be left as it
was, draft or committed. A resolution that fails SHALL be 422 and store nothing.

#### Scenario: the rules changed
- **WHEN** a binding's committed recipe was made by `household@3`, the ruleset is now at version 4,
  and the binding is resolved again
- **THEN** a new draft names `household@4`, and the committed recipe still names `household@3`

Pinned by: nothing yet.
