<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A rule tests only the facts of a closed vocabulary
A `<when>` SHALL name its fact with the `fact` attribute, and the fact SHALL be one of the
following, and no other. A fact is **text**, a **number** or a **flag** (`true` or `false`). The
file facts are visible to a rule of every scope; a stream fact is visible only to rules of its own
scope, where it describes the stream being decided.

| Fact | Scope | Shape | Values | Comes from |
|---|---|---|---|---|
| `kind` | file | text | what the item is: `episode`, `movie`, or, for an extra, one of the types SmdKit names for extras — `featurette`, `behindTheScenes`, `deletedScene`, `interview`, `trailer`, `scene`, `short`, `clip`, `themeSong`, `themeVideo` — or another type the container gives | the binding's item |
| `extra` | file | flag | whether the item is an extra: held in its container's extras rather than in a sequence, whatever its `kind` | the binding's item's place in its container |
| `profile` | file | text | the profile of the output being made, such as `mobile`; absent for the unqualified output | the output being resolved |
| `format` | file | text | the physical medium the source came from: `dvd`, `bluray` or `uhd`; absent for one that came from none | the first segment's input spec's `medium` |
| `duration` | file | number | seconds | the binding's joined spans |
| `video.codec` | video | text | the codec as `ffmpeg` names it: `h264`, `hevc`, `mpeg2video`, … | the input spec |
| `video.width` | video | number | pixels | the input spec |
| `video.height` | video | number | pixels | the input spec |
| `video.frameRate` | video | number | frames a second, such as `23.976` or `25` | the input spec |
| `video.interlaced` | video | flag | whether the stream is interlaced | the input spec |
| `video.hdr` | video | text | `hdr10` or `hlg`; absent for SDR video | derived from the input spec's transfer characteristic |
| `video.bitDepth` | video | number | bits per sample, such as `8` or `10` | the input spec |
| `audio.index` | audio | number | the stream's place from one among the joined media's audio streams, as `<track>` and the feature map count it | the input spec's order |
| `audio.codec` | audio | text | the codec as `ffmpeg` names it: `truehd`, `dts`, `ac3`, `eac3`, `aac`, `flac`, `pcm_s24le`, … | the input spec |
| `audio.lossless` | audio | flag | whether the stream is lossless: TrueHD, MLP, FLAC, ALAC, WavPack, TTA, APE, any PCM, and DTS-HD Master Audio | derived from the codec and its profile |
| `audio.channels` | audio | number | channel count, such as `2` or `6` | the input spec |
| `audio.language` | audio | text | the language, as the shortest ISO 639 code for it: `en`, `fr`, `es`, `yue` | the primary language subtag of the input spec's language tag |
| `audio.script` | audio | text | the script, in title case, such as `Latn` or `Hant`; absent when the tag names none | the script subtag of the input spec's language tag |
| `audio.region` | audio | text | the region, such as `GB`, `BR` or `419`; absent when the tag names none | the region subtag of the input spec's language tag |
| `audio.role` | audio | text | what the stream is for: `main`, `commentary`, `isolatedMusic`, `descriptive` or `other` | derived from the binding's feature map, then the input spec's marks |
| `audio.core` | audio | flag | whether the stream is the lossy core extracted from inside a lossless track | derived from the input spec's `coreOf` |
| `subtitle.index` | subtitle | number | as `audio.index`, among the subtitle streams | as `audio.index` |
| `subtitle.codec` | subtitle | text | the codec as `ffmpeg` names it: `hdmv_pgs_subtitle`, `dvd_subtitle`, `subrip`, … | the input spec |
| `subtitle.language` | subtitle | text | as `audio.language` | as `audio.language` |
| `subtitle.script` | subtitle | text | as `audio.script` | as `audio.script` |
| `subtitle.region` | subtitle | text | as `audio.region` | as `audio.region` |
| `subtitle.forced` | subtitle | flag | whether the stream carries only forced subtitles | derived from the input spec's `forced` mark |

A fact the source does not have — no `kind` where nothing names one, no `video.hdr` on SDR video,
no language tag — is **absent**. What an input spec holds is specified in
[input-specs](../input-specs/spec.md), and how each fact is derived from it in
[recipes](../recipes/spec.md).

#### Scenario: a file fact in a stream's rule
- **WHEN** a `<video>` rule carries `<when fact="profile" is="mobile"/>`
- **THEN** the ruleset reads, and the condition tests the profile the file is being made into

#### Scenario: a fact the vocabulary does not have
- **WHEN** a rule carries `<when fact="audio.bitrate" is="1"/>`
- **THEN** the ruleset is refused, saying `audio.bitrate` is not a fact a rule can test

#### Scenario: a stream fact in another scope's rule
- **WHEN** an `<audio>` rule carries `<when fact="video.width" lt="1000"/>`
- **THEN** the ruleset is refused, saying `video.width` cannot be tested in an `<audio>` rule

#### Scenario: one Spanish dub of two
- **WHEN** an `<audio>` rule carries `<when fact="audio.language" is="es"/>` and
  `<when fact="audio.region" is="419"/>`, and a source has audio tagged `es-419` and `es-ES`
- **THEN** the rule holds for the first stream and not the second

#### Scenario: an extra by where it is filed
- **WHEN** a `<video>` rule carries `<when fact="extra" is="true"/>`, and one binding's item is held in
  its container's extras with the type `movie`, and another's in a sequence with the type `movie`
- **THEN** the rule holds for the first item's video and not the second's

#### Scenario: one stream by its index
- **WHEN** an `<audio>` rule carries `<when fact="audio.index" is="2"/>`, and an entry has three audio
  streams
- **THEN** the rule holds for the second audio stream and for no other

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aRuleThatCannotBeReadIsRefused`,
`aRulesetSurvivesTheFile`), `Tests/SiloKitTests/FactsTests.swift`
(`losslessIsAFunctionOfCodecAndProfile`), `Tests/SiloKitTests/BindingTests.swift` (`factsAreDerivedFromWhatWasObserved`), `Tests/SiloKitTests/LayerTests.swift` (`aRulePicksOneStreamByItsIndex`),
`Tests/SiloTests/BindingRulesTests.swift` (`anExtraIsWhereItsContainerFilesItWhateverItsKind`).

### Requirement: The example ruleset is the one the design was written with
`Examples/household.xml` SHALL be a working ruleset: a `<video>`
rule `small-extras` that re-encodes the video of an extra, by the `extra` fact, narrower than 576 pixels with `libx264`
at preset `slow`, CRF 22 and `yuv420p`, deinterlacing what is marked interlaced; an `<audio>` rule
`lossless-main` that encodes a lossless stream that is not a commentary as FLAC; an `<audio>` rule
`commentary` that encodes a commentary as two-channel AAC at 160k; a condition-less copy rule for
each scope, last; and output `mkv`.

#### Scenario: the example reads as described
- **WHEN** `Examples/household.xml` is read
- **THEN** it is a ruleset of those six rules in that order, and its three copy rules are named
  `#4`, `#5` and `#6`

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`theExampleFileIsTheProposalsRules`).
