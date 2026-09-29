<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Rulesets

## Purpose

A ruleset is how a household writes down, once, the encoding decisions a person would otherwise
make for every file: which streams of a ripped file are kept, which are copied as they are, and
which are re-encoded, and with what. It is one XML document, written and read by a person, that
holds three things — the extraction policy the ingestion tool applies when it rips, an ordered list
of rules, and the output container. Each rule is about one kind of stream, tests facts about the
file and the stream, and says what to do with a stream it matches. For each stream the first
matching rule of its kind decides, and a stream no rule decides is an error, never a silent copy.

A silo holds rulesets by name, and every store of one is a new version the silo numbers and never
rewrites, so that a job can say which version of which ruleset made its file.

This spec is the whole of what a ruleset can say and how it is kept: the document, every element
and attribute, every fact a rule may test and the values it takes, every operator and action, how
rules are chosen between, what is refused, and how a silo stores rulesets. How facts are
discovered from a file, and what resolving a ruleset produces, are [recipes](../recipes/spec.md);
how a recipe becomes an `ffmpeg` invocation is [encoding](../encoding/spec.md); the routes that
read and store rulesets are [read-api](../read-api/spec.md). This spec covers the ruleset parts of
`Sources/SiloKit` and `Sources/SiloStore/RulesetStore.swift`.

Rationale: [Silo proposal — Encoding rules](../../../Proposals/Silo.md) — facts are discovered;
rules are written; a ruleset is immutable once named; no "or", no nesting, order is the only
precedence.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: A ruleset is one XML document of an extraction policy, rules and an output policy
A ruleset SHALL be a UTF-8 XML document whose root element is `<ruleset>`. The root's children
SHALL be, in any order: at most one `<extraction>` element, any number of rule elements —
`<video>`, `<audio>` and `<subtitle>` — and at most one `<output>` element. Comments and
whitespace MAY appear anywhere and mean nothing. The document order of the rule elements is
significant, since it decides which rule wins; the placement of `<extraction>` and `<output>`
among them is not. A ruleset with no rules is a valid document, though one that decides no
stream.

A complete ruleset reads:

```xml
<ruleset format="1" name="household">
  <extraction embeddedAudio="false" subtitles="true" embeddedSubtitles="true"/>

  <!-- A lossless main mix keeps everything, smaller. -->
  <audio id="lossless-main">
    <when fact="audio.lossless" is="true"/>
    <when fact="audio.role" ne="commentary"/>
    <encode codec="flac"/>
  </audio>

  <!-- Everything else, as it came. Written last, deliberately. -->
  <video><copy/></video>
  <audio><copy/></audio>
  <subtitle><copy/></subtitle>

  <output container="mkv"/>
</ruleset>
```

#### Scenario: the order of the rules is kept
- **WHEN** a document holds an `<output>` element, then an `<audio>` rule named `a`, then an
  `<extraction>` element, then an `<audio>` rule named `b`
- **THEN** it reads as a ruleset whose rules are `a` then `b`, with that extraction and output
  policy

#### Scenario: a ruleset with nothing in it
- **WHEN** the document is `<ruleset format="1" name="t"/>`
- **THEN** it reads as a ruleset with no rules, the default extraction policy and the default
  output policy

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`anEmptyRulesetHasTheToolsDefaults`,
`aRulesetSurvivesTheFile`).

### Requirement: The root names the format and the ruleset
The `<ruleset>` element SHALL carry `format`, an integer, and `name`, both required, and MAY
carry `version`, an integer. `format` is the version of this document's shape; this reader reads
format `1`, and a document of a higher format SHALL be refused. `name` and `version` are what the
person who wrote the document calls it: a silo SHALL know a stored ruleset by the name and version
it was stored under, whatever the document's own attributes say, and SHALL NOT rewrite them.

#### Scenario: a newer format is refused
- **WHEN** the document is `<ruleset format="2" name="t"/>`
- **THEN** it is refused because format 2 is newer than this reader

#### Scenario: the store's name wins
- **WHEN** a document whose root says `name="draft" version="9"` is stored as `household` and
  becomes its version 1
- **THEN** reading `household` at version 1 gives a ruleset named `household` at version 1, and
  the stored document still says `name="draft" version="9"`

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aDocumentThatIsNotARulesetIsRefused`);
the store's name winning is pinned by nothing yet.

### Requirement: The extraction policy says what the ingestion tool keeps when it rips
The `<extraction>` element SHALL carry the policy the ingestion tool applies when it rips a
disc, in three optional attributes, each `true` or `false`:

| Attribute | Means, when true | Default |
|---|---|---|
| `embeddedAudio` | keep the lossy core inside a lossless audio track as a stream of its own | `false` |
| `subtitles` | keep subtitle tracks at all | `true` |
| `embeddedSubtitles` | keep the forced-only subtitle stream MakeMKV derives from a subtitle track | `true` |

An absent element, or an absent attribute, SHALL mean the default. The policy decides what
streams the ripped file has; it takes no part in deciding what happens to them, which is the
rules' job. It lives in the ruleset because a person deciding what is kept and how it is encoded
is making one decision.

#### Scenario: the defaults
- **WHEN** a ruleset has no `<extraction>` element
- **THEN** its policy keeps no embedded audio cores, keeps subtitles, and keeps the forced-only
  subtitle streams

#### Scenario: a value that is not a boolean
- **WHEN** a ruleset carries `<extraction subtitles="yes"/>`
- **THEN** it is refused, naming the `subtitles` attribute and the value `yes`

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`anEmptyRulesetHasTheToolsDefaults`,
`aRulesetSurvivesTheFile`); the refusal is pinned by nothing yet.

### Requirement: The output policy names the container
The `<output>` element SHALL carry an optional `container` attribute naming the output file's
container format; absent, the container is `mkv`. `mkv` and `matroska` SHALL both mean `ffmpeg`'s
`matroska` format with the extension `.mkv`; any other value SHALL be handed to `ffmpeg` as the
format name and used as the extension as given. The value is not checked when the ruleset is read.

#### Scenario: the default container
- **WHEN** a ruleset has no `<output>` element
- **THEN** its output is written as `matroska`, with the extension `.mkv`

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`anEmptyRulesetHasTheToolsDefaults`).

### Requirement: A rule is a scope, a list of conditions and one action
A rule SHALL be an element named for the kind of stream it decides — `<video>`, `<audio>` or
`<subtitle>`, its scope — with an optional `id` attribute, any number of `<when>` children, its
conditions, and exactly one action child: `<copy/>`, `<drop/>` or `<encode>`. The rule matches a
stream when every one of its conditions holds; a rule with no conditions matches every stream of
its scope. There SHALL be no "or" and no nesting: a rule that wants either of two things is written
as two rules. A rule SHALL be named, wherever a silo reports which rule decided a stream, by its
`id`, or by `#n` for its 1-based position among all the rules of the document when it has no `id`.

#### Scenario: a rule with no conditions
- **WHEN** a ruleset holds `<subtitle><copy/></subtitle>`
- **THEN** that rule matches every subtitle stream that reaches it

#### Scenario: an unnamed rule is named by its position
- **WHEN** the third rule of a document, counting every scope, has no `id` and decides a stream
- **THEN** the stream is reported as decided by `#3`

#### Scenario: a rule with no action, or two
- **WHEN** a rule's only child is `<when fact="audio.codec" is="ac3"/>`, or it carries both
  `<copy/>` and `<drop/>`
- **THEN** the ruleset is refused, saying the rule has no action, or more than one

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aRuleThatCannotBeReadIsRefused`),
`Tests/SiloKitTests/ResolverTests.swift` (`theThreeRulesDecideAnEpisode`).

### Requirement: A rule tests only the facts of a closed vocabulary
A `<when>` SHALL name its fact with the `fact` attribute, and the fact SHALL be one of the
following, and no other. A fact is **text**, a **number** or a **flag** (`true` or `false`). The
file facts are visible to a rule of every scope; a stream fact is visible only to rules of its own
scope, where it describes the stream being decided.

| Fact | Scope | Shape | Values | Comes from |
|---|---|---|---|---|
| `kind` | file | text | what the item is: `episode`, `movie`, `featurette`, or another type of extra the container names, such as `interview`, `deletedScene`, `behindTheScenes`, `trailer`, `scene`, `short`, `clip` | the assignment |
| `profile` | file | text | the profile the file is being made into, such as `mobile`; absent for the unqualified presentation | the assignment |
| `format` | file | text | the disc the file was ripped from: `dvd`, `bluray` or `uhd` | the assignment, else MakeMKV's scan |
| `duration` | file | number | seconds | `ffprobe` |
| `video.codec` | video | text | the codec as `ffprobe` names it: `h264`, `hevc`, `mpeg2video`, … | `ffprobe` |
| `video.width` | video | number | pixels | `ffprobe` |
| `video.height` | video | number | pixels | `ffprobe` |
| `video.frameRate` | video | number | frames a second, such as `23.976` or `25` | `ffprobe` |
| `video.interlaced` | video | flag | whether the stream's field order is interlaced | `ffprobe` |
| `video.hdr` | video | text | `hdr10` or `hlg`; absent for SDR video | `ffprobe`'s transfer characteristic |
| `video.bitDepth` | video | number | bits per sample, such as `8` or `10` | `ffprobe` |
| `audio.codec` | audio | text | the codec as `ffprobe` names it: `truehd`, `dts`, `ac3`, `eac3`, `aac`, `flac`, `pcm_s24le`, … | `ffprobe` |
| `audio.lossless` | audio | flag | whether the stream is lossless: TrueHD, MLP, FLAC, ALAC, WavPack, TTA, APE, any PCM, and DTS-HD Master Audio | derived from the codec and its profile |
| `audio.channels` | audio | number | channel count, such as `2` or `6` | `ffprobe`, else MakeMKV's scan |
| `audio.language` | audio | text | the language tag as the file carries it, usually an ISO 639-2 code such as `eng` | `ffprobe`, else MakeMKV's scan |
| `audio.role` | audio | text | what the stream is for: `main`, `commentary`, `isolatedMusic`, `descriptive` or `other` | derived from the assignment, then the disc's flags, then the file's dispositions |
| `audio.core` | audio | flag | whether the stream is the lossy core extracted from inside a lossless track | MakeMKV's scan |
| `subtitle.codec` | subtitle | text | the codec as `ffprobe` names it: `hdmv_pgs_subtitle`, `dvd_subtitle`, `subrip`, … | `ffprobe` |
| `subtitle.language` | subtitle | text | as `audio.language` | `ffprobe`, else MakeMKV's scan |
| `subtitle.forced` | subtitle | flag | whether the stream carries only forced subtitles | the file's dispositions, or MakeMKV's scan |

A fact the file does not have — no `kind` on an unassigned file, no `video.hdr` on SDR video, no
language tag — is **absent**. How each fact is discovered and derived is specified in
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
(`losslessIsAFunctionOfCodecAndProfile`, `theRoleComesFromTheMostAuthoritativeSource`).

### Requirement: A condition applies exactly one of seven operators
A `<when>` SHALL carry exactly one operator attribute besides `fact`:

| Operator | Holds when the fact | Facts |
|---|---|---|
| `is="v"` | equals `v` | any |
| `ne="v"` | does not equal `v`, or is absent | any |
| `in="a,b,c"` | equals one of the comma-separated values, each trimmed of spaces | any |
| `lt="n"`, `le="n"`, `gt="n"`, `ge="n"` | is less than, at most, greater than, at least the number `n` | numbers only |

Equality SHALL follow the fact's shape: text compares as text, exactly and case-sensitively; a
number compares as a number when the value is one, so `video.width is="1920"` holds for a width
of 1920 and `video.frameRate is="25"` for a rate of 25.0; a flag equals `true` or `false`. An
absent fact SHALL hold for `ne` and for no other operator. A value is not checked against the
values its fact can take: a condition naming a value its fact never has is read, and never holds.

A `<when>` with no operator or with more than one, an ordering operator on a fact that is not a
number, and an ordering operator whose value is not a number SHALL each be refused.

#### Scenario: an absent fact holds only for ne
- **WHEN** an SDR video stream is tested by `<when fact="video.hdr" is="hdr10"/>` and by
  `<when fact="video.hdr" ne="hdr10"/>`
- **THEN** the first does not hold and the second does

#### Scenario: a number compares as a number
- **WHEN** a stream at 25 frames a second is tested by `<when fact="video.frameRate" ge="29.97"/>`
  and by `<when fact="video.frameRate" is="25"/>`
- **THEN** the first does not hold and the second does

#### Scenario: two operators on one condition
- **WHEN** a rule named `r` carries `<when fact="audio.codec" is="ac3" ne="dts"/>`
- **THEN** the ruleset is refused, saying rule `r`'s condition on `audio.codec` needs exactly one
  operator

#### Scenario: an ordering operator on text
- **WHEN** a rule carries `<when fact="audio.codec" lt="1"/>`
- **THEN** the ruleset is refused, saying `audio.codec` is not a number and cannot be compared
  with `lt`

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aRuleThatCannotBeReadIsRefused`),
`Tests/SiloKitTests/FactsTests.swift` (`anAbsentFactMatchesNothingExceptNotEqual`).

### Requirement: An action copies, drops or re-encodes the stream
A rule's action SHALL be one of three. `<copy/>` keeps the stream in the output exactly as it is
in the source. `<drop/>` leaves the stream out of the output, and every later stream of its kind
moves up one place. `<encode codec="…">` keeps the stream, re-encoded with the encoder `codec`
names as `ffmpeg` names its encoders — `libx264`, `libx265`, `flac`, `aac` — and the settings the
element carries. `codec` SHALL be required. The encoders a ruleset's actions name are what a node's
`ffmpeg` must have to take on a file made by it.

#### Scenario: a dropped stream moves the rest up
- **WHEN** a file's first of three audio streams is decided by a `<drop/>` rule and the other two
  by `<copy/>`
- **THEN** the output has two audio streams, the source's second and third, as its first and
  second

#### Scenario: an encode without a codec
- **WHEN** a rule's action is `<encode/>`
- **THEN** the ruleset is refused, saying `<encode>` is missing its `codec` attribute

Pinned by: `Tests/SiloKitTests/ResolverTests.swift`
(`aDroppedStreamRenumbersWhatFollowsAndWarnsAboutAMappedOne`),
`Tests/SiloKitTests/RulesetFileTests.swift` (`aRuleThatCannotBeReadIsRefused`).

### Requirement: An encode's settings are ffmpeg's, named for what they do
`<encode>` SHALL accept these optional attributes, each applied to the one output stream being
encoded:

| Attribute | Means | Value | `ffmpeg` option |
|---|---|---|---|
| `preset` | the encoder's speed-for-size preset | text, such as `slow` | `-preset` |
| `crf` | constant-quality target, lower is better | integer | `-crf` |
| `bitrate` | target bitrate | as `ffmpeg` takes it, such as `160k` | `-b` |
| `channels` | down- or up-mix to this many channels | integer | `-ac` |
| `pixelFormat` | the output pixel format | such as `yuv420p` | `-pix_fmt` |

and these optional children, applied in document order as one filter chain:

| Child | Means |
|---|---|
| `<deinterlace mode="auto"/>` | deinterlace the frames the stream marks interlaced; `mode` defaults to `auto` |
| `<deinterlace mode="always"/>` | deinterlace every frame |
| `<scale width="…" height="…"/>` | resize; a dimension left out follows the other, keeping the aspect ratio |
| `<filter>text</filter>` | an `ffmpeg` filter written out, for one no element names |

plus any number of `<option name="…" value="…"/>` children, each handed to `ffmpeg` as
`-<name> <value>` for the stream — the way to reach an encoder setting that has no attribute, such
as FLAC's `compression_level`. Two options of one name SHALL keep the last. An integer attribute
whose value is not an integer, and a deinterlace mode other than `auto` or `always`, SHALL be
refused. Text values are not checked when the ruleset is read; `ffmpeg` judges them when it runs.
How the settings become one `ffmpeg` invocation is [encoding](../encoding/spec.md)'s.

#### Scenario: an extra made small
- **WHEN** a `<video>` rule's action is
  `<encode codec="libx264" preset="slow" crf="22" pixelFormat="yuv420p"><deinterlace/></encode>`
  and it decides an interlaced stream
- **THEN** the stream is encoded with `libx264` at preset `slow`, CRF 22 and pixel format
  `yuv420p`, deinterlacing the frames marked interlaced

#### Scenario: an option with no attribute of its own
- **WHEN** an `<audio>` rule's action is
  `<encode codec="flac"><option name="compression_level" value="8"/></encode>`
- **THEN** the stream is encoded as FLAC with `-compression_level 8`

#### Scenario: a deinterlace mode the reader does not know
- **WHEN** an encode carries `<deinterlace mode="sometimes"/>`
- **THEN** the ruleset is refused, naming the `mode` attribute and the value `sometimes`

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aRulesetSurvivesTheFile`),
`Tests/EncoderTests/ArgumentsTests.swift` (`theRecipeIsTheArgumentList`,
`aReencodedVideoCarriesItsFilters`); the deinterlace refusal is pinned by nothing yet.

### Requirement: For each stream, the first matching rule of its scope decides
A ruleset SHALL decide a file's streams one at a time: the video stream, then each audio stream,
then each subtitle stream, each in the file's order. For each, the rules of the stream's scope
SHALL be tried in document order, and the first whose conditions all hold decides; later rules of
the scope are not consulted. Order is the only precedence: a more specific rule written after a
more general one never decides. A rule with no conditions, written last in its scope, is therefore
that scope's catch-all. Only a file's first video stream is decided; a file with more than one
video stream has the others left out of the output, and is told so as a hint.

#### Scenario: order, not specificity
- **WHEN** an audio scope holds a rule matching every lossless stream, encoding it as FLAC,
  followed by a rule matching lossless commentaries, encoding them as AAC, and a lossless
  commentary is decided
- **THEN** it is encoded as FLAC by the first rule, and the second never decides a stream

#### Scenario: the catch-all takes what falls through
- **WHEN** an audio scope holds a commentary rule and then `<audio><copy/></audio>`, and a file
  has a main mix and a commentary
- **THEN** the commentary is decided by the commentary rule and the main mix is copied by the
  catch-all

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`theFirstMatchingRuleWins`,
`theThreeRulesDecideAnEpisode`).

### Requirement: A stream no rule decides stops the file
A stream that no rule of its scope decides SHALL fail the whole resolution, never be copied,
dropped or guessed past. The failure SHALL read `no rule decides <kind> <n> (<facts>)`, where
`<n>` is the stream's place from one among streams of its kind and `<facts>` describes it: a video
stream as its codec and size, then `interlaced` and its HDR kind where they apply; an audio stream
as its codec, its profile where it has one, its channel count as `<n>ch`, its language or `und`,
its role, then `lossless` and `core` where they apply; a subtitle stream as its codec, its language
or `und`, then `forced` where it applies. That is enough to write the rule that would have decided
it.

#### Scenario: a ruleset with no video rule
- **WHEN** a ruleset holds audio and subtitle rules only, and decides a file whose video is H.264
  at 1920 by 1080, progressive and SDR
- **THEN** resolution fails with `no rule decides video 1 (h264 1920x1080)`

#### Scenario: an audio stream that falls through
- **WHEN** a ruleset's only audio rule matches commentaries, and a file's third audio stream is a
  two-channel English AC-3 main mix with no profile
- **THEN** resolution fails with `no rule decides audio 3 (ac3 2ch eng main)`

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`aStreamNoRuleDecidesIsAnError`).

### Requirement: A document that cannot be read is refused whole
A document SHALL be read whole or refused whole, with the first thing wrong named; no part of a
refused document is used. It SHALL be refused, in these words, when:

| Case | Refusal |
|---|---|
| it is not well-formed XML, including a truncated document | `malformed XML: <reason>` |
| its root element is not `<ruleset>` | `the document is not rooted at <ruleset>` |
| its `format` is newer than the reader's | `ruleset format <n> is newer than this reader (1)` |
| a required attribute is missing | `<<element>> is missing its <attribute> attribute` |
| an integer, boolean or deinterlace mode is not one | `<<element> <attribute>="<value>"> is not a value this reader accepts` |
| an element appears where the document has no such element | `<<name>> is not an element of a ruleset` |
| a fact is not in the vocabulary | `"<fact>" is not a fact a rule can test` |
| a stream fact is tested in another scope's rule | `"<fact>" cannot be tested in a <<scope>> rule` |
| a condition has no operator, or more than one | `rule <rule>: <when fact="<fact>"> needs exactly one of is, ne, in, lt, le, gt, ge` |
| an ordering operator is applied to a fact that is not a number | `"<fact>" is not a number and cannot be compared with <operator>` |
| a rule has no action | `rule <rule> has no <copy/>, <drop/> or <encode>` |
| a rule has more than one action | `rule <rule> has more than one action` |

where `<rule>` is the rule's `id`, or its scope's element name when it has none. An attribute the
reader does not know SHALL be ignored, as SHALL a second `<extraction>` or `<output>` element.

#### Scenario: an element the document does not have
- **WHEN** a ruleset's root holds a `<rule/>` element
- **THEN** it is refused with `<rule> is not an element of a ruleset`, not skipped

#### Scenario: a truncated document
- **WHEN** the document is `<ruleset format="1" name="t"><audio>` and nothing more
- **THEN** it is refused as malformed XML, not read with its tags closed for it

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aDocumentThatIsNotARulesetIsRefused`,
`aRuleThatCannotBeReadIsRefused`); the ignored attributes and elements are pinned by nothing yet.

### Requirement: A silo keeps each ruleset as the documents it was given
A silo SHALL keep its rulesets under `rulesets/<name>/<version>.xml` in its state directory — the
name the folder, the version the file's name — and SHALL keep each document's bytes exactly as
they were given, so a comment or a layout a person wrote survives. Reading a ruleset SHALL give the
document at the version asked for, or at the latest version when none is, and a ruleset read from
the store SHALL be named and numbered by where it was found.

#### Scenario: a stored version reads back byte for byte
- **WHEN** a document with a comment in it is stored as `household`, another document is stored
  as `household` after it, and version 1 is read back
- **THEN** the document returned is, byte for byte, the first document stored, comment included

Pinned by: `Tests/SiloTests/ServerTests.swift` (`rulesetsAreVersionedAndTheOperatorGateHolds`).

### Requirement: Every store is a new version the silo numbers, and a version is never rewritten
A store SHALL be given the next version of its name — the latest plus one, or 1 for a new name —
chosen and written under one lock, so no two stores receive the same number. A version SHALL NOT
be rewritten: a file already on disk under the number chosen is refused as already there. A
document SHALL be read before it is stored, and a document the reader refuses SHALL NOT be stored.
A name that is empty, contains a `/`, or begins with a `.` SHALL be refused. There is no way to
delete, rename or replace a version: a job names the version it was resolved against, and that
version must still say what it said.

#### Scenario: two stores are numbered in order
- **WHEN** the same document is stored as `household` twice
- **THEN** the first store is version 1, the second version 2, and the latest version of
  `household` is 2

#### Scenario: a document that is not a ruleset is not stored
- **WHEN** a document testing `<when fact="nope" is="1"/>` is stored
- **THEN** it is refused with `"nope" is not a fact a rule can test`, and no version is added

#### Scenario: a name a ruleset cannot have
- **WHEN** a document is stored as `.hidden`
- **THEN** it is refused, and nothing is written

Pinned by: `Tests/SiloTests/ServerTests.swift` (`rulesetsAreVersionedAndTheOperatorGateHolds`).
The name and already-there refusals are pinned by nothing yet.

### Requirement: The example ruleset is the one the design was written with
`Examples/household.xml` SHALL be a working ruleset: the default extraction policy; a `<video>`
rule `small-extras` that re-encodes the video of an extra narrower than 576 pixels with `libx264`
at preset `slow`, CRF 22 and `yuv420p`, deinterlacing what is marked interlaced; an `<audio>` rule
`lossless-main` that encodes a lossless stream that is not a commentary as FLAC; an `<audio>` rule
`commentary` that encodes a commentary as two-channel AAC at 160k; a condition-less copy rule for
each scope, last; and output `mkv`.

#### Scenario: the example reads as described
- **WHEN** `Examples/household.xml` is read
- **THEN** it is a ruleset of those six rules in that order, and its three copy rules are named
  `#4`, `#5` and `#6`

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`theExampleFileIsTheProposalsRules`).
