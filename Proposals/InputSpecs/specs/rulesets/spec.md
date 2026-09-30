<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## RENAMED Requirements

- FROM: `### Requirement: The extraction policy says which of an origin's streams a source file keeps`
- TO: `### Requirement: The extraction policy says which streams a producer keeps in a mezzanine`

## MODIFIED Requirements

### Requirement: A rule tests only the facts of a closed vocabulary
A `<when>` SHALL name its fact with the `fact` attribute, and the fact SHALL be one of the
following, and no other. A fact is **text**, a **number** or a **flag** (`true` or `false`). The
file facts are visible to a rule of every scope; a stream fact is visible only to rules of its own
scope, where it describes the stream being decided.

| Fact | Scope | Shape | Values | Comes from |
|---|---|---|---|---|
| `kind` | file | text | what the item is: `episode`, `movie`, `featurette`, or another type of extra the container names, such as `interview`, `deletedScene`, `behindTheScenes`, `trailer`, `scene`, `short`, `clip` | the assignment |
| `profile` | file | text | the profile the file is being made into, such as `mobile`; absent for the unqualified presentation | the assignment |
| `format` | file | text | the physical medium the mezzanine came from: `dvd`, `bluray` or `uhd`; absent for one that came from none | the assignment, else the input spec's `medium` |
| `duration` | file | number | seconds | the input spec |
| `video.codec` | video | text | the codec as `ffmpeg` names it: `h264`, `hevc`, `mpeg2video`, … | the input spec |
| `video.width` | video | number | pixels | the input spec |
| `video.height` | video | number | pixels | the input spec |
| `video.frameRate` | video | number | frames a second, such as `23.976` or `25` | the input spec |
| `video.interlaced` | video | flag | whether the stream is interlaced | the input spec |
| `video.hdr` | video | text | `hdr10` or `hlg`; absent for SDR video | derived from the input spec's transfer characteristic |
| `video.bitDepth` | video | number | bits per sample, such as `8` or `10` | the input spec |
| `audio.codec` | audio | text | the codec as `ffmpeg` names it: `truehd`, `dts`, `ac3`, `eac3`, `aac`, `flac`, `pcm_s24le`, … | the input spec |
| `audio.lossless` | audio | flag | whether the stream is lossless: TrueHD, MLP, FLAC, ALAC, WavPack, TTA, APE, any PCM, and DTS-HD Master Audio | derived from the codec and its profile |
| `audio.channels` | audio | number | channel count, such as `2` or `6` | the input spec |
| `audio.language` | audio | text | an ISO 639-2 code, such as `eng` | the input spec |
| `audio.role` | audio | text | what the stream is for: `main`, `commentary`, `isolatedMusic`, `descriptive` or `other` | derived from the assignment, then the input spec's marks |
| `audio.core` | audio | flag | whether the stream is the lossy core extracted from inside a lossless track | derived from the input spec's `coreOf` |
| `subtitle.codec` | subtitle | text | the codec as `ffmpeg` names it: `hdmv_pgs_subtitle`, `dvd_subtitle`, `subrip`, … | the input spec |
| `subtitle.language` | subtitle | text | as `audio.language` | the input spec |
| `subtitle.forced` | subtitle | flag | whether the stream carries only forced subtitles | derived from the input spec's `forced` mark |

A fact the mezzanine does not have — no `kind` on an unassigned file, no `video.hdr` on SDR video,
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

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aRuleThatCannotBeReadIsRefused`,
`aRulesetSurvivesTheFile`), `Tests/SiloKitTests/FactsTests.swift`
(`losslessIsAFunctionOfCodecAndProfile`); derivation from the input spec is pinned by nothing yet.

### Requirement: The extraction policy says which streams a producer keeps in a mezzanine
The `<extraction>` element SHALL carry the policy a producer applies when it obtains a mezzanine —
which of the streams available to it the mezzanine keeps — in three optional attributes, each
`true` or `false`:

| Attribute | Means, when true | Default |
|---|---|---|
| `embeddedAudio` | keep the lossy core inside a lossless audio track as a stream of its own | `false` |
| `subtitles` | keep subtitle tracks at all | `true` |
| `embeddedSubtitles` | keep the forced-only subtitle stream derived from a subtitle track | `true` |

An absent element, or an absent attribute, SHALL mean the default. The silo stores the policy with
the ruleset and serves it to producers; it does not apply it. Each attribute speaks to streams a
producer may be able to keep or leave out — a lossy core it could extract, a forced-only stream it
could derive — and has no effect for a producer that has no such streams to offer. The policy
decides what streams the mezzanine has; it takes no part in deciding what happens to them, which is
the rules' job. It lives in the ruleset because a person deciding what is kept and how it is
encoded is making one decision.

#### Scenario: the defaults
- **WHEN** a ruleset has no `<extraction>` element
- **THEN** its policy keeps no embedded audio cores, keeps subtitles, and keeps the forced-only
  subtitle streams

#### Scenario: a value that is not a boolean
- **WHEN** a ruleset carries `<extraction subtitles="yes"/>`
- **THEN** it is refused, naming the `subtitles` attribute and the value `yes`

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`anEmptyRulesetHasTheToolsDefaults`,
`aRulesetSurvivesTheFile`); the refusal is pinned by nothing yet.
