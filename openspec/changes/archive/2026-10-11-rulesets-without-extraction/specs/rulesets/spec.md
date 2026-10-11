<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## RENAMED Requirements
- FROM: `### Requirement: A ruleset is one XML document of an extraction policy, rules and outputs`
- TO: `### Requirement: A ruleset is one XML document of rules and outputs`

## REMOVED Requirements

### Requirement: The extraction policy says which streams a producer keeps in a source
**Reason**: It spoke only to a producer, and the silo applied none of it; everything it said is said
as drop rules, which a producer reads through the resolver's dry run.
**Migration**: None: no silo holds a ruleset yet. A rule dropping `audio.core` streams, or every
subtitle, says what the policy's attributes said.

## MODIFIED Requirements

### Requirement: A ruleset is one XML document of rules and outputs
A ruleset SHALL be a UTF-8 XML document whose root element is `<ruleset>`. The root's children
SHALL be, in any order: any number of rule elements —
`<video>`, `<audio>` and `<subtitle>` — and any number of `<output>` elements. Comments and
whitespace MAY appear anywhere and mean nothing. The document order of the rule elements is
significant, since it decides which rule wins, and so is the order of the `<output>` elements,
which is the order a binding's recipes come in; the placement of either among the rules is not. A ruleset with no rules is a valid document, though one that decides no
stream.

A complete ruleset reads:

```xml
<ruleset format="1" name="household">
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
- **WHEN** a document holds an `<output>` element, then an `<audio>` rule named `a`, then a comment,
  then an `<audio>` rule named `b`
- **THEN** it reads as a ruleset whose rules are `a` then `b`, with that output

#### Scenario: a ruleset with nothing in it
- **WHEN** the document is `<ruleset format="1" name="t"/>`
- **THEN** it reads as a ruleset with no rules and one unqualified `mkv` output

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`anEmptyRulesetHasTheToolsDefaults`,
`aRulesetSurvivesTheFile`, `aRulesetMakesEachOutputItDeclares`).

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
reader does not know SHALL be ignored. What a source keeps is not an element of a ruleset: a
producer reads it from the rules, as the streams every output drops.

#### Scenario: an element the document does not have
- **WHEN** a ruleset's root holds a `<rule/>` element
- **THEN** it is refused with `<rule> is not an element of a ruleset`, not skipped

#### Scenario: what a source keeps is said by rules
- **WHEN** a ruleset's root holds an `<extraction subtitles="false"/>` element
- **THEN** it is refused with `<extraction> is not an element of a ruleset`

#### Scenario: a truncated document
- **WHEN** the document is `<ruleset format="1" name="t"><audio>` and nothing more
- **THEN** it is refused as malformed XML, not read with its tags closed for it

Pinned by: `Tests/SiloKitTests/RulesetFileTests.swift` (`aDocumentThatIsNotARulesetIsRefused`,
`aRuleThatCannotBeReadIsRefused`, `anOutputMadeTwiceIsRefused`); the ignored attributes are pinned by
nothing yet.

### Requirement: The example ruleset is the one the design was written with
`Examples/household.xml` SHALL be a working ruleset: a `<video>`
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

### Requirement: A container's rules are a layer written in the ruleset language
The version files a container's `<rules>` names, as [library](../library/spec.md) describes, SHALL
each hold one root `<rules>` element of rule elements — `<video>`, `<audio>` and `<subtitle>` — read
exactly as the rules of a ruleset are read, and nothing else: an `<output>` or any
other element SHALL be refused as not an element of a container's rules. A version is refused whole,
as a ruleset is, and its unnamed rules are named `#n` by their position among its rules. A version
file once written SHALL NOT be edited by the silo: a change is the next version. A container's layer
SHALL stand ahead of the layers of the containers above it.

#### Scenario: a container's rules read as a ruleset's
- **WHEN** a container's version in force holds `<video id="keep"><when fact="kind" ne="episode"/><copy/></video>`
- **THEN** it reads as one video rule named `keep`

#### Scenario: no outputs in a container's rules
- **WHEN** a container's version in force holds an `<output container="mp4"/>` element
- **THEN** it is refused, saying `<output>` is not an element of a container's rules

Pinned by: `Tests/SiloKitTests/LayerTests.swift` (`aLayersRulesAreReadAsARulesetsAndNothingElse`), `Tests/SiloTests/StackTests.swift` (`anApplicationResolvesThroughTheLineagesRulesInForce`).

### Requirement: An entry's rules are a stack of layers, nearest first
The rules that decide an entry SHALL be a stack of layers: every layer the entry has, nearest first,
as the requirements on each kind of layer place them, and last the ruleset applied, at the version
resolved. A container with no sidecar, or whose sidecar has no `<rules>`, contributes no layer. For
each stream, the rules of the stream's scope SHALL be tried layer by layer, and within a layer in
document order; the first that matches decides, and no later rule in any layer is consulted. Every
output SHALL be resolved through the same stack, with `profile` set to its profile. The outputs SHALL be the applied ruleset's alone.

#### Scenario: a container's rule speaks first
- **WHEN** the ruleset applied encodes every lossless audio stream as FLAC, the item's container has
  one rule copying lossless audio, and the entry has one lossless audio stream and one lossy one
- **THEN** the lossless stream is copied by the container's rule, and the lossy stream falls
  through to the ruleset's rules

#### Scenario: the nearer container wins
- **WHEN** a serial's rules copy commentaries, the series holding it has rules dropping them, and an
  episode of the serial has a commentary
- **THEN** the commentary is copied by the serial's rule

#### Scenario: a condition-less container rule ends its scope
- **WHEN** a container's rules hold `<audio><copy/></audio>`
- **THEN** every audio stream of every item below it is copied, and no audio rule of the ruleset
  applied decides any of them

Pinned by: `Tests/SiloKitTests/LayerTests.swift` (`aContainersRuleSpeaksFirstAndTheRestFallThrough`, `theNearerContainerWins`, `aConditionlessContainerRuleEndsItsScope`).
