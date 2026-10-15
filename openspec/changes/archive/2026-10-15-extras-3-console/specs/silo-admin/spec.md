<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A draft is edited in a form built from the rule language
SiloAdmin SHALL edit a draft in a form: rules added, edited, deleted, and dragged by a handle to
reorder within their scope; outputs added, edited and deleted. Each rule SHALL read as its clauses:
IF its first condition and AND each other, then THEN its action, an encode followed by WHERE its first
setting and AND each other. A rule after the first of its scope SHALL read OTHERWISE IF in place of IF,
and a rule with no condition SHALL read ALWAYS its action when it is its scope's first rule and
OTHERWISE its action after another. A rule's facts SHALL be named without its scope's prefix, and its
id shown only when it has one. A condition's fact SHALL be chosen from the rule language's facts,
offering only the tests the fact takes, named in words, and, where the fact's values are a closed set,
only those values, or, for `kind`, the types SmdKit names, `episode` and `movie` first and then the
extra types, offered beside a field that takes any; a `one of` SHALL take each value in a field of its own. An action SHALL be copy,
drop, or an encode with its settings as fields, its codec offered by the name a condition on the codec
uses, written as the encoder `ffmpeg` lists for it, and a new encode starting with a codec of the
rule's scope. An encode SHALL offer only the settings its codec takes — a video encode its preset,
CRF, bitrate and pixel format, an audio encode its channels and, unless its codec is lossless, its
bitrate, and a subtitle encode none — and SHALL write no other. Every change SHALL be made by splicing the draft's text, so the text view shows exactly
what changed. While the text cannot be read, the form SHALL show the reader's refusal and make no
change.

#### Scenario: a rule moved in the form
- **WHEN** the operator drags the commentary rule above the lossless rule
- **THEN** the text shows the rule moved with its comment, and no other difference

#### Scenario: a fact's tests
- **WHEN** the operator adds a condition on `audio.channels`
- **THEN** the form offers the seven tests, and for `audio.role` only `is`, `ne` and `in`, with its
  roles as the values

#### Scenario: a rule read in the form
- **WHEN** a video rule encodes with `libx265` and `crf` 20 when `video.interlaced` is `true`, and the
  scope's next rule drops when `video.width` is below 720
- **THEN** the first reads IF `interlaced is true` THEN `encode` WHERE `codec is hevc` AND `crf is 20`,
  and the second OTHERWISE IF `width < 720` THEN `drop`

#### Scenario: a rule with no condition
- **WHEN** a subtitle rule copies with no condition
- **THEN** it reads ALWAYS `copy` as its scope's first rule, and OTHERWISE `copy` after another

#### Scenario: an item's kind
- **WHEN** the operator adds a condition on `kind`
- **THEN** the form offers `episode`, `movie`, and then the extra types from `featurette` to
  `themeVideo`, and takes a type it does not offer

#### Scenario: tests named in words
- **WHEN** the operator chooses a condition's test
- **THEN** `ne` is offered as `is not`, `in` as `one of`, and `lt`, `le`, `gt` and `ge` as `<`, `≤`,
  `>` and `≥`

#### Scenario: an encode's codec
- **WHEN** the operator makes a new video rule an encode and chooses the codec `hevc`
- **THEN** its codec starts as `h264`, and the document's encode names the encoder `libx265`

#### Scenario: an encode's settings
- **WHEN** the operator makes an audio rule an encode with `aac`, then changes its codec to `flac`
- **THEN** the form offers its bitrate and channels, then only its channels, and the document's
  encode carries no bitrate

Pinned by: `Tests/SiloKitTests/RulesetTextTests.swift` (`aMoveLeavesEverythingElseAsItWas`, for the
splice a drag makes, and `aFactOffersTheTestsAndValuesItTakes`, for what a condition offers), and
`Tests/SiloAdminKitTests/RuleSentencesTests.swift` (`aRuleReadsAsIfAndThenWhere`,
`aLaterRuleIsReachedOnlyOtherwise`, `testsAreNamedInWordsAndFactsWithoutTheirScope`,
`anEncodeIsOfferedByCodecAndWritesItsEncoder`, `anEncodeTakesTheSettingsItsCodecHas` and
`aKindIsOfferedFromTheTypesSmdKitNames`); the form itself is shell rendering, and the shell has
no test target.
