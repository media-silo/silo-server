<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## RENAMED Requirements

- FROM: `### Requirement: The extraction policy says which of an origin's streams a source file keeps`
- TO: `### Requirement: The extraction policy says which streams a producer keeps in a source`
- FROM: `### Requirement: A ruleset is one XML document of an extraction policy, rules and an output policy`
- TO: `### Requirement: A ruleset is one XML document of an extraction policy, rules and outputs`
- FROM: `### Requirement: The output policy names the container`
- TO: `### Requirement: The outputs name what is made of every entry`

## MODIFIED Requirements

### Requirement: A ruleset is one XML document of an extraction policy, rules and outputs
A ruleset SHALL be a UTF-8 XML document whose root element is `<ruleset>`. The root's children
SHALL be, in any order: at most one `<extraction>` element, any number of rule elements —
`<video>`, `<audio>` and `<subtitle>` — and any number of `<output>` elements. Comments and
whitespace MAY appear anywhere and mean nothing. The document order of the rule elements is
significant, since it decides which rule wins, and so is the order of the `<output>` elements,
which is the order a binding's recipes come in; the placement of either among the rules is not. A ruleset with no rules is a valid document, though one that decides no
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
  <output profile="mobile" container="mp4"/>
</ruleset>
```

#### Scenario: the order of the rules is kept
- **WHEN** a document holds an `<output>` element, then an `<audio>` rule named `a`, then an
  `<extraction>` element, then an `<audio>` rule named `b`
- **THEN** it reads as a ruleset whose rules are `a` then `b`, with that extraction policy and that
  output

#### Scenario: a ruleset with nothing in it
- **WHEN** the document is `<ruleset format="1" name="t"/>`
- **THEN** it reads as a ruleset with no rules, the default extraction policy and one unqualified
  `mkv` output

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`anEmptyRulesetHasTheToolsDefaults`,
`aRulesetSurvivesTheFile`).

### Requirement: The outputs name what is made of every entry
Each `<output>` element SHALL name one presentation the ruleset makes of every entry it is applied
to: an optional `profile`, absent for the unqualified presentation, and an optional `container`
naming the output file's container format, absent meaning `mkv`. A binding SHALL be resolved once
for each output, with the `profile` fact set to the output's profile. A ruleset with no `<output>`
SHALL make one unqualified `mkv` output. Two outputs with the same profile, or two without one,
SHALL be refused. `mkv` and `matroska` SHALL both mean `ffmpeg`'s `matroska` format with the
extension `.mkv`; any other value SHALL be handed to `ffmpeg` as the format name and used as the
extension as given. The container is not checked when the ruleset is read.

#### Scenario: the default container
- **WHEN** a ruleset has no `<output>` element
- **THEN** it makes one unqualified output, written as `matroska`, with the extension `.mkv`

#### Scenario: a full and a mobile presentation
- **WHEN** a ruleset holds `<output container="mkv"/>` then `<output profile="mobile" container="mp4"/>`
- **THEN** it makes two outputs, the unqualified `mkv` first and the `mobile` `mp4` second

#### Scenario: one profile twice
- **WHEN** a ruleset holds two `<output profile="mobile"/>` elements
- **THEN** it is refused, saying the profile `mobile` is made twice

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`anEmptyRulesetHasTheToolsDefaults`); more
than one output is pinned by nothing yet.

### Requirement: A rule tests only the facts of a closed vocabulary
A `<when>` SHALL name its fact with the `fact` attribute, and the fact SHALL be one of the
following, and no other. A fact is **text**, a **number** or a **flag** (`true` or `false`). The
file facts are visible to a rule of every scope; a stream fact is visible only to rules of its own
scope, where it describes the stream being decided.

| Fact | Scope | Shape | Values | Comes from |
|---|---|---|---|---|
| `kind` | file | text | what the item is: `episode`, `movie`, `featurette`, or another type of extra the container names, such as `interview`, `deletedScene`, `behindTheScenes`, `trailer`, `scene`, `short`, `clip` | the binding's item |
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
| `audio.codec` | audio | text | the codec as `ffmpeg` names it: `truehd`, `dts`, `ac3`, `eac3`, `aac`, `flac`, `pcm_s24le`, … | the input spec |
| `audio.lossless` | audio | flag | whether the stream is lossless: TrueHD, MLP, FLAC, ALAC, WavPack, TTA, APE, any PCM, and DTS-HD Master Audio | derived from the codec and its profile |
| `audio.channels` | audio | number | channel count, such as `2` or `6` | the input spec |
| `audio.language` | audio | text | an ISO 639-2 code, such as `eng` | the input spec |
| `audio.role` | audio | text | what the stream is for: `main`, `commentary`, `isolatedMusic`, `descriptive` or `other` | derived from the binding's feature map, then the input spec's marks |
| `audio.core` | audio | flag | whether the stream is the lossy core extracted from inside a lossless track | derived from the input spec's `coreOf` |
| `subtitle.codec` | subtitle | text | the codec as `ffmpeg` names it: `hdmv_pgs_subtitle`, `dvd_subtitle`, `subrip`, … | the input spec |
| `subtitle.language` | subtitle | text | as `audio.language` | the input spec |
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

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aRuleThatCannotBeReadIsRefused`,
`aRulesetSurvivesTheFile`), `Tests/SiloKitTests/FactsTests.swift`
(`losslessIsAFunctionOfCodecAndProfile`); derivation from the input spec is pinned by nothing yet.

### Requirement: The extraction policy says which streams a producer keeps in a source
The `<extraction>` element SHALL carry the policy a producer applies when it obtains a source —
which of the streams available to it the source keeps — in three optional attributes, each
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
decides what streams the source has; it takes no part in deciding what happens to them, which is
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
| two outputs have the same profile, or neither has one | `the profile <profile> is made twice`, or `the unqualified output is made twice` |

where `<rule>` is the rule's `id`, or its scope's element name when it has none. An attribute the
reader does not know SHALL be ignored, as SHALL a second `<extraction>` element.

#### Scenario: an element the document does not have
- **WHEN** a ruleset's root holds a `<rule/>` element
- **THEN** it is refused with `<rule> is not an element of a ruleset`, not skipped

#### Scenario: a truncated document
- **WHEN** the document is `<ruleset format="1" name="t"><audio>` and nothing more
- **THEN** it is refused as malformed XML, not read with its tags closed for it

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aDocumentThatIsNotARulesetIsRefused`,
`aRuleThatCannotBeReadIsRefused`); the ignored attributes and element, and the outputs' refusals, are pinned by nothing yet.
