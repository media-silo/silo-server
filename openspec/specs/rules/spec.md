<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Rules

## Purpose

The rules capability is how a household writes down, once, the encoding decisions a person would
otherwise make per file: the closed vocabulary of facts a rule may test, the ruleset XML document
the rules live in, the extraction policy that travels beside them, and the resolver that turns a
ruleset and a file's facts into a recipe — one decision per stream, each naming its rule, plus the
layout the output will have. This spec covers `Sources/SiloKit`.

Rationale: [Silo proposal — Encoding rules](../../../Proposals/Silo.md) — facts are discovered;
rules are written; a decision is recorded with what it decided.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: Facts are a closed, scoped vocabulary

A rule SHALL test only the keys of `FactKey`, a closed enum: the file-level facts `kind`,
`profile`, `format` and `duration`; the video facts `video.codec`, `video.width`, `video.height`,
`video.frameRate`, `video.interlaced`, `video.hdr` and `video.bitDepth`; the audio facts
`audio.codec`, `audio.lossless`, `audio.channels`, `audio.language`, `audio.role` and `audio.core`;
and the subtitle facts `subtitle.codec`, `subtitle.language` and `subtitle.forced`. A scoped key
SHALL be visible only in its own scope; a file-level key SHALL be visible in every scope. The
numeric facts SHALL be `duration`, `video.width`, `video.height`, `video.frameRate`,
`video.bitDepth` and `audio.channels`, and no others. Audio and subtitle facts are indexed from one
among the streams of their kind — the way a player's menu counts and the way the sidecar's
`<track audio="n">` counts — while `absoluteIndex` keeps `ffprobe`'s index across every stream in
the file. A rule reads facts and never writes them.

#### Scenario: a file-level fact is visible in a stream's scope
- **WHEN** a `<video>` rule carries `<when fact="profile" is="mobile"/>`
- **THEN** the condition parses and reads the profile the file is being made into

#### Scenario: a number fact reads as a number
- **WHEN** a rule tests `<when fact="video.frameRate" ge="29.97"/>` against a file whose video runs at 25 frames a second
- **THEN** the condition parses, the fact reads as the number 25, and the condition does not hold

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aRulesetSurvivesTheFile`), `Tests/SiloKitTests/FactsTests.swift` (`anAbsentFactMatchesNothingExceptNotEqual`).

### Requirement: Losslessness and role are each derived in one place

`AudioFacts.isLossless` SHALL be a function of codec and profile only, so that the tool at rip
time, the resolver at registration and the node at encode time agree: TrueHD, MLP, FLAC, ALAC,
WavPack, TTA, APE and any `pcm_` codec are lossless, DTS is lossless only when its profile is
DTS-HD Master Audio (the DTS-HD High Resolution profile is not), and anything else is not.

`AudioRole` SHALL be derived from the sources in order of authority: the assignment's feature map
first, then MakeMKV's stream flags (bits 1 and 2 are the disc's own commentary marks, bit 4 is
descriptive), then the file's own dispositions (`comment` is commentary, `visual_impaired` or
`descriptions` is descriptive). When none of them speaks the role is `main`. A stream title that
merely says "commentary" SHALL NOT set the role; it is reported as a hint instead. The `core`
fact — the lossy core inside a lossless track, the same audio again, smaller and worse — SHALL
come from MakeMKV's scan; without a scan no stream is a core.

#### Scenario: dts is lossless only as Master Audio
- **WHEN** `isLossless` is called for `("dts", "DTS-HD MA")`, `("dts", "DTS-HD HRA")`, `("pcm_s24le", nil)` and `("ac3", nil)`
- **THEN** the answers are true, false, true and false

#### Scenario: the assignment outranks the disc and the file
- **WHEN** the assignment maps a stream to isolated music while MakeMKV's flags mark it commentary and the file's disposition says `comment`
- **THEN** the role is `isolatedMusic`

#### Scenario: every source silent
- **WHEN** no assignment maps the stream, the scan's flags are clear and the dispositions hold only `default`
- **THEN** the role is `main`

Pinned by: `Tests/SiloKitTests/FactsTests.swift` (`losslessIsAFunctionOfCodecAndProfile`, `theRoleComesFromTheMostAuthoritativeSource`).

### Requirement: Facts are merged once from the probe, the scan and the assignment

`SourceFacts` SHALL be built from `ffprobe`'s probe of the file, MakeMKV's scan of the title it
was ripped from, and the assignment (the role map, `kind`, `profile` and `format`), in one
initialiser. The probe speaks first for what the file holds: duration, the first video stream
(further video streams are reported as a hint and not described), and each stream's codec,
channels, language and title. The scan fills in what the file did not say — a language, a channel
count, whether a track is a core or forced-only — but only when the scan's kept-track count for
the kind equals the probed stream count; a count that does not match SHALL leave the scan's
per-track facts for that kind unapplied and SHALL be reported as a hint. The disc `format` is a
file-level fact and still applies from the scan when the assignment does not give one. A hint is
shown to a person and is never a fact a rule can test.

#### Scenario: a scan whose counts do not match is not applied
- **WHEN** the scan kept 2 audio tracks but the ripped file has 1
- **THEN** the stream's role is derived without the scan's flags, the hint reads "MakeMKV kept 2 audio tracks but the file has 1; the scan's audio facts were not applied", and the disc format still comes from the scan

#### Scenario: a title that says commentary is a hint, not a role
- **WHEN** a stream is titled "Commentary with the director" and nothing else marks it
- **THEN** its role stays `main` and a hint on stream 3 reads: titled "Commentary with the director" but nothing marks it a commentary; assign it to a feature if it is one

Pinned by: `Tests/SiloKitTests/FactsTests.swift` (`factsAreMergedFromTheProbeTheScanAndTheAssignment`, `aScanWhoseCountsDoNotMatchIsNotApplied`).

### Requirement: The ruleset is a named, versioned XML document

A ruleset file SHALL be XML rooted at `<ruleset format="1" name="…">`, encoded UTF-8, with `name`
required and `version` optional. A file whose root is not `<ruleset>`, that is not well-formed
XML, or whose `format` is higher than this reader's `1`, SHALL be refused. `format` is written
always; `version` is written only once the silo has assigned one on storing the ruleset, and a
version is immutable once stored. Top-level children other than `<extraction>`, rule elements and
`<output>` SHALL be refused as unknown elements. An absent `<extraction>` or `<output>` element
SHALL yield the defaults (the extraction policy of the requirement below; `<output>` container
`mkv`). Writing and reading SHALL round-trip: the proposal's three rules with a version, a
subtitle scale and an encoder option survive the file unchanged. `Examples/household.xml` SHALL
read as exactly the proposal's ruleset: `small-extras`, `lossless-main` and `commentary` followed
by a condition-less copy rule for each scope, extraction `embeddedAudio="false" subtitles="true"
embeddedSubtitles="true"`, output `mkv`.

#### Scenario: not a ruleset
- **WHEN** the document is `<rules/>`, or `<ruleset format="2" name="t"/>`, or a truncated `<ruleset format="1" name="t"><audio>`
- **THEN** reading is refused with `notARuleset`, `unsupportedFormat(2)` and a malformed-XML error respectively

#### Scenario: an unknown element
- **WHEN** a top-level `<rule/>` element appears
- **THEN** reading is refused with `unknownElement("rule")`, not silently skipped

#### Scenario: the example file is the proposal's ruleset
- **WHEN** `Examples/household.xml` is read from the repository
- **THEN** it equals the six-rule `Ruleset` the resolver tests are written against

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aDocumentThatIsNotARulesetIsRefused`, `anEmptyRulesetHasTheToolsDefaults`, `aRulesetSurvivesTheFile`, `theExampleFileIsTheProposalsRules`).

### Requirement: A rule is a scope, a conjunction of conditions and one action

A rule SHALL be an element named for its scope — `<video>`, `<audio>` or `<subtitle>` — with an
optional `id`, `<when>` children for its conditions, and exactly one action child: `<copy/>`,
`<drop/>` or `<encode …>`. Every condition must hold for the rule to match; there is no "or" and
no nesting — a rule that wants either of two things is two rules. `<encode>` SHALL require a
`codec` attribute and accept optional `preset`, `crf`, `bitrate`, `channels` and `pixelFormat`
attributes, plus child elements: `<deinterlace mode="auto|always"/>` (`auto` when the attribute
is absent), `<scale width="…" height="…"/>` (either dimension omissible, keeping the aspect
ratio), `<filter>` carrying raw ffmpeg filter text, and `<option name="…" value="…"/>` pairs kept
sorted by name so that two settings meaning the same thing compare equal. A rule with no action,
two actions, an `<encode>` with no `codec`, a deinterlace mode that is not `auto` or `always`, or
an unrecognised child element SHALL be a parse error.

#### Scenario: a rule with no action is refused
- **WHEN** a rule's children are `<when fact="audio.codec" is="a"/>` and nothing else
- **THEN** reading is refused with `noAction(rule: "r")`

#### Scenario: one action only
- **WHEN** a rule carries both `<copy/>` and `<drop/>`
- **THEN** reading is refused with `multipleActions(rule: "r")`

#### Scenario: an encode without a codec is refused
- **WHEN** a rule's action is a bare `<encode/>`
- **THEN** reading is refused, naming the missing `codec` attribute

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aRuleThatCannotBeReadIsRefused`, `aRulesetSurvivesTheFile`).

### Requirement: A condition applies exactly one of seven operators

A `<when fact="…">` SHALL carry exactly one of `is`, `ne`, `in`, `lt`, `le`, `gt` and `ge`; zero
or two SHALL be a parse error naming the rule and the fact. `is` is equality, `ne` its negation,
`in` membership in a comma-separated set, and `lt`, `le`, `gt`, `ge` compare numbers. An ordering
operator on a fact that is not numeric SHALL be a parse error (`notNumeric`), and an ordering
operator's value that is not a number SHALL be a parse error (`invalidValue`). Comparison follows
the fact's shape: a number compared against text parses the text as a number when it can, so
`video.width is 1920` holds for a width of 1920; a flag compares as `true` or `false`. An absent
fact holds for `ne` and for nothing else — `hdr ne hdr10` holds for SDR video, and `hdr is
hdr10`, `kind in episode` and `duration lt 100` do not hold for a file that has no HDR kind, no
kind and no duration.

#### Scenario: two operators on one condition
- **WHEN** a rule carries `<when fact="audio.codec" is="a" ne="b"/>`
- **THEN** reading is refused with `oneTestRequired(rule: "r", fact: "audio.codec")`

#### Scenario: an ordering operator on a non-numeric fact
- **WHEN** a rule carries `<when fact="audio.codec" lt="1"/>`
- **THEN** reading is refused with `notNumeric(fact: "audio.codec", operator: "lt")`

#### Scenario: an absent fact matches nothing except ne
- **WHEN** a file has no HDR kind and a rule tests `video.hdr is hdr10` and another tests `video.hdr ne hdr10`
- **THEN** the first does not hold and the second does

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aRuleThatCannotBeReadIsRefused`), `Tests/SiloKitTests/FactsTests.swift` (`anAbsentFactMatchesNothingExceptNotEqual`).

### Requirement: An unknown or out-of-scope fact is a parse error

A `<when>` naming a key outside the closed vocabulary SHALL be refused as `unknownFact`, and a
scoped fact tested in a rule of another scope SHALL be refused as `factOutOfScope` — a parse
error, not a rule that never matches.

#### Scenario: a fact the vocabulary does not have
- **WHEN** a rule carries `<when fact="audio.bitrate" is="1"/>`
- **THEN** reading is refused with `unknownFact("audio.bitrate")`

#### Scenario: a video fact in an audio rule
- **WHEN** an `<audio>` rule carries `<when fact="video.width" lt="1"/>`
- **THEN** reading is refused with `factOutOfScope(fact: "video.width", scope: .audio)`

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aRuleThatCannotBeReadIsRefused`).

### Requirement: The extraction policy is the ruleset's sibling element

One `<extraction>` element at the top of the ruleset SHALL carry the policy the ingestion tool
applies at rip time — `embeddedAudio`, `subtitles` and `embeddedSubtitles` as
`true`/`false` — because deciding what is kept at the rip and how what is kept is encoded is one
decision made in one document. An absent element SHALL mean the tool's defaults:
`embeddedAudio="false" subtitles="true" embeddedSubtitles="true"` — every track on the disc, minus
the lossy cores of lossless tracks, keeping subtitles and the forced-only streams MakeMKV derives
from them. A value that is not `true` or `false` SHALL be a parse error. The policy stays a rule
about the rip; it takes no part in resolving a recipe.

#### Scenario: an empty ruleset has the tool's defaults
- **WHEN** a ruleset file carries no `<extraction>` element
- **THEN** its extraction policy is embeddedAudio false, subtitles true, embeddedSubtitles true

#### Scenario: a written policy survives the file
- **WHEN** a ruleset whose `subtitles` policy is false is written and read back
- **THEN** the read ruleset's policy still has subtitles false

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`anEmptyRulesetHasTheToolsDefaults`, `aRulesetSurvivesTheFile`).

### Requirement: The first matching rule in a scope decides the stream

Resolution SHALL walk the video stream, then each audio stream, then each subtitle stream, and
for each walk the scope's rules in document order; the first rule whose conditions all hold
decides, and order is the only precedence there is. A rule with no conditions always holds, so a
condition-less copy rule written last is the catch-all for its scope — the convention the
household ruleset's final three rules follow. A rule without an `id` is named in the recipe by
its 1-based position in the document, as `#n`.

#### Scenario: order, not specificity, decides
- **WHEN** the household ruleset resolves an episode whose second audio stream is a lossless commentary
- **THEN** the `commentary` rule decides it, because `lossless-main` excludes commentaries; rewritten so `lossless-main` only tests losslessness, `lossless-main` decides the same stream

#### Scenario: the catch-alls are the condition-less rules written last
- **WHEN** the household ruleset resolves a Blu-ray episode with a TrueHD main mix, an AC-3 commentary, an AC-3 stereo mix and two subtitle streams
- **THEN** the video and the stereo mix fall through to the condition-less copy rules named `#4` and `#5`, and the subtitles are copied by `#6`

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`theFirstMatchingRuleWins`, `theThreeRulesDecideAnEpisode`).

### Requirement: A stream no rule decides is an error

A stream that no rule in its scope decides SHALL fail resolution with a `ResolutionError` naming
the stream's kind, its index from one among streams of the kind, and its facts — never a silent
copy. The error carries enough to write the rule that would have decided.

#### Scenario: an undecided video stream
- **WHEN** the household ruleset's three catch-all rules are removed and it resolves a Blu-ray episode
- **THEN** resolution throws "no rule decides video 1 (h264 1920x1080)"

#### Scenario: an undecided audio stream
- **WHEN** only the video catch-all is restored
- **THEN** resolution throws "no rule decides audio 3 (ac3 2ch eng main)"

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`aStreamNoRuleDecidesIsAnError`).

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
