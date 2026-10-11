<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The stored rulesets are read at their latest version, or the one asked for
`GET /v1/rulesets` SHALL answer 200 with one `RulesetSummary` per ruleset: its `name`; its `version`,
the latest number; its `standard`, the standard's head; and its `versions`, every version ascending,
each with its `branch`, its `parent` and `presentations`, the number of placed presentations whose
committed recipe names it. `GET /v1/rulesets/{name}` SHALL answer 200 with a `RulesetDocument`: the
`name`, the `version`, its `branch`, the `document` as the XML that was stored, byte for byte, and the
`reading` — each rule in document order with the name a recipe calls it by
(its `id`, or `#n` for its position), its scope, its conditions as fact, test and value, and its
action, and the outputs; a `version` query parameter SHALL select a version other than the latest. The
reading SHALL name the ruleset by where it was stored, whatever the document's own attributes say. A
name the silo does not hold, or a version it does not hold, SHALL be 404.

#### Scenario: the list, the latest and a named version
- **WHEN** `household` has been stored twice and a client asks
  `GET /v1/rulesets`, `GET /v1/rulesets/household` and
  `GET /v1/rulesets/household?version=1`
- **THEN** the list reads `household@2` with versions 1 and 2 on the standard, the latest answers
  version 2, and version 1's `document` equals, byte for byte, the document first stored

#### Scenario: names and versions the silo does not hold
- **WHEN** a client asks `GET /v1/rulesets/household?version=9` or
  `GET /v1/rulesets/nothing`
- **THEN** the answer is 404

#### Scenario: a reading names its rules as a recipe does
- **WHEN** a ruleset's document holds a rule with `id="commentary"` and, fifth in the document, a
  condition-less `<audio><copy/></audio>`
- **THEN** the reading names the first `commentary` and the second `#5`, each with its scope, its
  conditions and its action

#### Scenario: what each version made
- **WHEN** a ruleset's version 1 made three placed presentations and its version 2 none
- **THEN** the list reports `presentations` 3 for version 1 and 0 for version 2

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`, `aRulesetIsReadWholeADraftCheckedAndAStoreBasedOnItsHead`),
`Tests/SiloTests/CheckTests.swift` (`eachVersionReportsThePresentationsItMade`).
