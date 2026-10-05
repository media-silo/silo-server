<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Facts and recipes

## Purpose

A ruleset says what to do with a stream given its facts; this capability is where the facts come
from and what applying a ruleset to them produces. Facts are derived once — from a binding, the
input specs of its sources, and the output being made — with the derived facts, losslessness, role
and core-ness, each derived in one place. Applying a ruleset to a binding resolves it once for each
output it makes, and each resolution is kept as a draft recipe: one decision per stream, each naming
the rule that made it, the layout the output will have, and the warnings a person should read
before anything is encoded. A draft may be adjusted stream by stream, or discarded; making a job
from it commits it, and a committed recipe never changes. What a ruleset is, the facts a rule may
test and how rules are chosen between are [rulesets](../rulesets/spec.md); what a producer observes
of a source is [input-specs](../input-specs/spec.md); what a binding says is
[bindings](../bindings/spec.md). This spec covers the facts, the resolver and the stored recipe in
`Sources/SiloKit`, the recipe store in `Sources/SiloStore`, and the routes that apply a ruleset to a
binding and adjust and discard a draft.

The household ruleset the scenarios below resolve is `Examples/household.xml`, described in
[rulesets](../rulesets/spec.md): `small-extras` re-encodes a narrow extra's video with `libx264`,
`lossless-main` encodes a lossless non-commentary stream as FLAC, `commentary` encodes a commentary
as two-channel AAC at 160k, and three condition-less copy rules, `#4` to `#6`, catch the rest.

Rationale: [Silo proposal — Encoding rules](../../../Proposals/Silo.md) — rules are written; a
decision is recorded with what it decided; [Ingestion — Recipes](../../../Proposals/Ingestion.md) —
facts are observed by a producer and derived by the silo.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: The recipe records one decision per stream, each naming its rule

Resolution SHALL yield a `Recipe` naming its ruleset as `name` or `name@version`, holding the
decisions in source order — the video stream, then each audio stream, then each subtitle
stream — where each decision records the stream's kind, its index from one among its kind, its
absolute index, the rule's `id` or `#n` position, and the action. The recipe SHALL carry the
ruleset's output policy and its warnings, expose the encoders it needs as the set of `ffmpeg`
codec names its encode actions use (what a node has to have to claim it), and round-trip through
JSON unchanged, so a job can store it and "what did this file get, and why" is answered by
reading, not re-resolving.

#### Scenario: the household ruleset decides an episode
- **WHEN** the household ruleset resolves a Blu-ray episode with a TrueHD main mix, an AC-3 commentary, an AC-3 stereo mix and two subtitle streams
- **THEN** the six decisions name rules `#4`, `lossless-main`, `commentary`, `#5`, `#6`, `#6`; the first audio stream becomes FLAC, the commentary becomes AAC at 160k stereo, the rest copy; the recipe's encoders are flac and aac; and there are no warnings

#### Scenario: a recipe survives JSON
- **WHEN** a resolved recipe is encoded to JSON and decoded back
- **THEN** it equals the original

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`theThreeRulesDecideAnEpisode`, `aRecipeSurvivesJSON`).

### Requirement: The output layout maps source streams to output streams

The recipe's layout SHALL list the streams the output will have — video first, then the surviving
audio streams, then the surviving subtitles, each in source order — with every entry pointing back
at its source stream by per-kind index and absolute index, and numbered with an `outputIndex`
from one among output streams of the kind and an `outputAbsoluteIndex` from zero across the whole
output, `ffmpeg`'s own count. The layout is computed before the encode, so the new presentation's
`<track>` indices are known without opening the output: `tracks(for:)` SHALL renumber the
binding's feature map through it, and a mapping whose stream the recipe drops SHALL be left
out.

#### Scenario: a dropped stream renumbers what follows
- **WHEN** the household ruleset gains rules dropping lossless audio and forced subtitles and resolves the episode, whose commentary is source audio 2
- **THEN** the layout is video, audio, audio, subtitle; source audio 2 becomes output audio 1 and source audio 3 becomes output audio 2; the feature mapped to audio 2 renumbers to `audio="1"`; and the features mapped to the dropped streams are left out of the renumbered map

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`aDroppedStreamRenumbersWhatFollowsAndWarnsAboutAMappedOne`).

### Requirement: A feature mapped to a dropped stream is a warning, not an error

A feature mapped to a stream the recipe drops SHALL appear in the recipe's `warnings` and SHALL
NOT fail resolution — a mobile presentation without the isolated score is a reasonable thing to
make, and the warning changes what the sidecar will say. A source with no video stream SHALL
likewise be warned about rather than fail.

#### Scenario: two mapped features land on dropped streams
- **WHEN** the dropping ruleset of the layout requirement resolves the episode with features mapped to audio 1, audio 2 and subtitle 2
- **THEN** resolution succeeds with exactly the warnings "feature music1 is mapped to audio 1, which this recipe drops" and "feature signs is mapped to subtitle 2, which this recipe drops"

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`aDroppedStreamRenumbersWhatFollowsAndWarnsAboutAMappedOne`).

### Requirement: Resolution is a pure function of the facts and the ruleset

`RecipeResolver.resolve` SHALL take every input as a value — the file's facts, the ruleset, the
binding's feature map — and return the recipe or throw `ResolutionError`, with no file read
and no `ffprobe` or `ffmpeg` run. The two derived facts, the closed vocabulary and the file
reader exist so that the resolver never needs to ask anything else.

#### Scenario: the proposal's rules resolve against a literal DVD featurette
- **WHEN** the household ruleset resolves literal facts for a 352x288 interlaced MPEG-2 featurette with one AC-3 stereo track
- **THEN** the video is encoded by `small-extras` as libx264, preset slow, CRF 22, yuv420p, deinterlaced automatically, and the audio falls to the catch-all copy — with no tool and no file involved

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`aSmallExtraIsReencoded`).

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

Pinned by: `Tests/SiloKitTests/FactsTests.swift` (`losslessIsAFunctionOfCodecAndProfile`), `Tests/SiloKitTests/BindingTests.swift`
(`factsAreDerivedFromWhatWasObserved`).

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

Pinned by: `Tests/SiloKitTests/BindingTests.swift` (`factsAreDerivedFromWhatWasObserved`, `anEpisodeOutOfAPlayAllTitleIsItsChapterSpan`).

### Requirement: Applying a ruleset to a binding makes a draft recipe for each output
`POST /v1/bindings/{id}/recipes`, behind the operator's token, SHALL apply a ruleset to a binding:
it SHALL take the ruleset's name, an optional version — the latest when left out — and optionally
the outputs to make, by profile, an object with no profile naming the unqualified output, and every
output when left out. It SHALL resolve the binding once for each output it makes, deriving the facts
for that output and resolving the ruleset's rules against them, and SHALL store each recipe as a
`draft`, naming its binding, its output, and the ruleset version resolved, and answer 201 with them.
A ruleset or version the silo does not hold, or an output the ruleset does not make, SHALL be 400; a
binding the silo does not hold SHALL be 404. If any output's resolution fails because a stream no
rule decides, the application SHALL be refused with 422 carrying the resolver's report, and nothing
stored; the binding stays, since the rules were incomplete and the binding was not wrong. Every
recipe the binding already has SHALL be left as it was, draft or committed, so applying a newer
version of the ruleset, or another ruleset, is the same operation again. `GET /v1/recipes/{id}`
SHALL answer one recipe, with no token asked, or 404 for an id the silo does not know.

#### Scenario: two outputs, two recipes
- **WHEN** a ruleset whose outputs are an unqualified `mkv` and a `mobile` `mp4`, and whose video
  rules are one scaling to 720 lines when `profile` is `mobile`, then a condition-less copy, is
  applied to a binding
- **THEN** the binding has two draft recipes, each naming that ruleset and version; the mobile one
  scales the video and the unqualified one copies it

#### Scenario: an output no rule can make
- **WHEN** a ruleset with a mobile output but no audio rule that holds when `profile` is `mobile` is
  applied to a binding
- **THEN** the application is refused with 422, naming the undecided audio stream; nothing is stored,
  and the binding stays

#### Scenario: the rules changed
- **WHEN** a binding's committed recipe was made by `household@3`, the ruleset is now at version 4,
  and `household` is applied to the binding again
- **THEN** a new draft names `household@4`, and the committed recipe still names `household@3`

#### Scenario: another ruleset for the same binding
- **WHEN** a binding has a draft from `household`, and the operator applies `restoration` to it
- **THEN** the binding has a draft from each, and the first is as it was

Pinned by: `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`, `aBindingOrAnApplicationThatCannotBeMadeKeepsNothing`). Applying a newer version of a ruleset to a binding that holds a committed recipe is pinned by nothing yet: recipes are committed by making a job, in the fourth step.

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

Pinned by: `Tests/SiloKitTests/BindingTests.swift` (`anAdjustmentReplacesADecisionAndRecordsWhatItReplaced`, `aDroppedStreamRenumbersTheRestAndWarns`, `anAdjustmentThatNamesNothingOrTwiceIsRefused`), `Tests/SiloStoreTests/RecipeStoreTests.swift` (`aDraftIsAdjustedAndRestored`, `aCommittedRecipeNeverChanges`), `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`).

### Requirement: A recipe is committed once, and never changes after
Making a job from a draft recipe SHALL commit it, and a committed recipe SHALL NOT change: neither
its decisions, its adjustments nor its ruleset version. `DELETE /v1/recipes/{id}`, behind the
operator's token, SHALL discard a draft and SHALL be 409 for a committed recipe.

#### Scenario: a draft discarded
- **WHEN** the operator discards a draft no job was made from
- **THEN** the recipe is gone, and its binding's other recipes are as they were

Pinned by: `Tests/SiloStoreTests/RecipeStoreTests.swift` (`aCommittedRecipeNeverChanges`, `aDraftIsDiscardedAndTheRestStay`), `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`). Committing by making a job is pinned by nothing yet: jobs are made from recipes in the fourth step.
