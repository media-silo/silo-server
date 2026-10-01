<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## RENAMED Requirements

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
