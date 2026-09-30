<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Facts and recipes

## Purpose

A ruleset says what to do with a stream given its facts; this capability is where the facts come
from and what applying a ruleset to them produces. Facts are discovered — merged once from
`ffprobe`'s probe of the source file, the origin scan where there is one, and the assignment
that says what the file is — with the two derived facts, losslessness and role, each derived in
one place. Resolving a ruleset against a file's facts yields a recipe: one decision per stream,
each naming the rule that made it, the layout the output will have, and the warnings a person
should read before anything is encoded. What a ruleset is, the facts a rule may test and how rules
are chosen between are [rulesets](../rulesets/spec.md), which also defines the source file, its
origin and the origin scan; today the one kind of origin scan is MakeMKV's scan of the disc title
a file was read from, and the requirements below name it where its specifics matter. This spec covers the facts and the
resolver in `Sources/SiloKit`.

The household ruleset the scenarios below resolve is `Examples/household.xml`, described in
[rulesets](../rulesets/spec.md): `small-extras` re-encodes a narrow extra's video with `libx264`,
`lossless-main` encodes a lossless non-commentary stream as FLAC, `commentary` encodes a commentary
as two-channel AAC at 160k, and three condition-less copy rules, `#4` to `#6`, catch the rest.

Rationale: [Silo proposal — Encoding rules](../../../Proposals/Silo.md) — facts are discovered;
rules are written; a decision is recorded with what it decided.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: Losslessness and role are each derived in one place

`AudioFacts.isLossless` SHALL be a function of codec and profile only, so that the tool at ingestion,
the resolver at registration and the node at encode time agree: TrueHD, MLP, FLAC, ALAC,
WavPack, TTA, APE and any `pcm_` codec are lossless, DTS is lossless only when its profile is
DTS-HD Master Audio (the DTS-HD High Resolution profile is not), and anything else is not.

`AudioRole` SHALL be derived from the sources in order of authority: the assignment's feature map
first, then the origin scan's stream flags (in MakeMKV's scan, bits 1 and 2 are the disc's own
commentary marks and bit 4 is descriptive), then the file's own dispositions (`comment` is commentary, `visual_impaired` or
`descriptions` is descriptive). When none of them speaks the role is `main`. A stream title that
merely says "commentary" SHALL NOT set the role; it is reported as a hint instead. The `core`
fact — the lossy core inside a lossless track, the same audio again, smaller and worse — SHALL
come from the origin scan; without one no stream is a core.

#### Scenario: dts is lossless only as Master Audio
- **WHEN** `isLossless` is called for `("dts", "DTS-HD MA")`, `("dts", "DTS-HD HRA")`, `("pcm_s24le", nil)` and `("ac3", nil)`
- **THEN** the answers are true, false, true and false

#### Scenario: the assignment outranks the origin and the file
- **WHEN** the assignment maps a stream to isolated music while the origin scan's flags mark it commentary and the file's disposition says `comment`
- **THEN** the role is `isolatedMusic`

#### Scenario: every source silent
- **WHEN** no assignment maps the stream, the scan's flags are clear and the dispositions hold only `default`
- **THEN** the role is `main`

Pinned by: `Tests/SiloKitTests/FactsTests.swift` (`losslessIsAFunctionOfCodecAndProfile`, `theRoleComesFromTheMostAuthoritativeSource`).

### Requirement: Facts are merged once from the probe, the scan and the assignment

`SourceFacts` SHALL be built from `ffprobe`'s probe of the source file, the origin scan when the
ingestion tool sent one, and the assignment (the role map, `kind`, `profile` and `format`), in one
initialiser. The probe speaks first for what the file holds: duration, the first video stream
(further video streams are reported as a hint and not described), and each stream's codec,
channels, language and title. The scan fills in what the file did not say — a language, a channel
count, whether a track is a core or forced-only — but only when the scan's kept-track count for
the kind equals the probed stream count; a count that does not match SHALL leave the scan's
per-track facts for that kind unapplied and SHALL be reported as a hint. The origin's `format` is a
file-level fact and still applies from the scan when the assignment does not give one. A hint is
shown to a person and is never a fact a rule can test. Audio and subtitle streams SHALL be
numbered from one among the streams of their kind — the way a player's menu counts and the way the
sidecar's `<track audio="n">` counts — while each keeps `ffprobe`'s `absoluteIndex` across every
stream in the file.

#### Scenario: a scan whose counts do not match is not applied
- **WHEN** MakeMKV's scan kept 2 audio tracks but the source file has 1
- **THEN** the stream's role is derived without the scan's flags, the hint reads "MakeMKV kept 2 audio tracks but the file has 1; the scan's audio facts were not applied", and the origin's format still comes from the scan

#### Scenario: a title that says commentary is a hint, not a role
- **WHEN** a stream is titled "Commentary with the director" and nothing else marks it
- **THEN** its role stays `main` and a hint on stream 3 reads: titled "Commentary with the director" but nothing marks it a commentary; assign it to a feature if it is one

Pinned by: `Tests/SiloKitTests/FactsTests.swift` (`factsAreMergedFromTheProbeTheScanAndTheAssignment`, `aScanWhoseCountsDoNotMatchIsNotApplied`).

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
assignment's feature map through it, and a mapping whose stream the recipe drops SHALL be left
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
assignment's feature map — and return the recipe or throw `ResolutionError`, with no file read
and no `ffprobe` or `ffmpeg` run. The two derived facts, the closed vocabulary and the file
reader exist so that the resolver never needs to ask anything else.

#### Scenario: the proposal's rules resolve against a literal DVD featurette
- **WHEN** the household ruleset resolves literal facts for a 352x288 interlaced MPEG-2 featurette with one AC-3 stereo track
- **THEN** the video is encoded by `small-extras` as libx264, preset slow, CRF 22, yuv420p, deinterlaced automatically, and the audio falls to the catch-all copy — with no tool and no file involved

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`aSmallExtraIsReencoded`).
