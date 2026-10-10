<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The stored rulesets are read at their latest version, or the one asked for
`GET /v1/rulesets` SHALL answer 200 with one `RulesetSummary` per ruleset: its `name`; its `version`,
the latest number; its `standard`, the standard's head; and its `versions`, every version ascending,
each with its `branch`, its `parent` and `presentations`, the number of placed presentations whose
committed recipe names it. `GET /v1/rulesets/{name}` SHALL answer 200 with a `RulesetDocument`: the
`name`, the `version`, its `branch`, the `document` as the XML that was stored, byte for byte, and the
`reading` — the extraction policy, each rule in document order with the name a recipe calls it by
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
(`rulesetsAreVersionedAndTheOperatorGateHolds`). The versions, the reading and the presentations
each version made are pinned by nothing yet.

### Requirement: Every ruleset store is a new version, and is the operator's
`PUT /v1/rulesets/{name}` with a JSON `RulesetDocument` SHALL store the `document` as the next version
of the name — on the standard, or on the `branch` the body names — and answer 201 with the version the
silo assigned; a `version` in the body SHALL be ignored on a store, since numbering is the silo's. A
document the ruleset reader refuses SHALL NOT be stored, and the answer SHALL be 400 with a `Problem`
whose `detail` says why. The body MAY carry `basedOn`, the head of the branch it is stored to that the
document was made from, or zero for a name that must be new; the store SHALL then go ahead only if
that is still the head, decided under the lock the version number is taken under, and otherwise SHALL
store nothing and answer 409 with a `Problem` naming the head. Without `basedOn` the store SHALL go
ahead whatever the head. The route is the operator's.

#### Scenario: two stores are numbered in order
- **WHEN** the operator puts the household ruleset at `/v1/rulesets/household`
  twice
- **THEN** the answers are 201 with `version` 1 and then 2

#### Scenario: a document that is not a ruleset is refused
- **WHEN** the operator puts a document testing `<when fact="nope" is="1"/>`
- **THEN** the answer is 400 with `not a fact a rule can test` in the problem
  detail, and nothing is stored

#### Scenario: two editors from one base
- **WHEN** two stores to the standard are each based on version 3, the standard's head
- **THEN** the first is 201 with version 4, and the second is 409 naming version 4 and stores nothing

#### Scenario: a new name, and one that is not new
- **WHEN** a store is based on zero for a name the silo has no version of, and another based on zero
  for `household`
- **THEN** the first is 201 with version 1, and the second is 409

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`). A store based on a head is pinned by nothing yet.

## ADDED Requirements

### Requirement: A rules document is checked as a store would check it, and nothing is stored
`POST /v1/rulesets/{name}/check` with a `RulesetDocument` SHALL check the name as a store checks it and
read the document as a store reads it, and SHALL answer 200 with the reading a `GET` of the stored
document would carry, or 400 with a `Problem` whose detail is the one a store of the same document
under the same name would give. It SHALL store nothing and change nothing, and SHALL be answered
without a token, as the resolver's dry run is.

#### Scenario: a mistyped fact
- **WHEN** a client checks a document testing `<when fact="subtitle.forcd" is="true"/>`
- **THEN** the answer is 400 with the detail a store would give, and no version is added

#### Scenario: a draft that reads
- **WHEN** a client checks a document the reader accepts
- **THEN** the answer is 200 with its reading, and no version is added

Pinned by: nothing yet.

### Requirement: A draft's impact on placed presentations is read, and nothing is stored
`POST /v1/rulesets/{name}/impact` with a draft document and the version it is based on SHALL answer
200 with every placed presentation whose committed recipe names a version on the base's branch,
resolved again as the background check resolves it but with the draft in place of the ruleset, the
rest of its stack as it stands, and reported as the out-of-date report reports a presentation — its
container, item and file, the stack that made it, the streams that would change from what to what,
and its binding's sources with their copies, never their secrets — leaving out each the draft would
make as it was made. A document the reader refuses SHALL be 400 as a check answers it, and a ruleset or
base the silo does not hold 404. It SHALL record nothing and change nothing, and SHALL be answered
without a token.

#### Scenario: a draft's impact is what the check finds once it is in force
- **WHEN** a draft's impact is read, the draft is then stored as the head of its base's branch with
  nothing else changing, and the background check finishes
- **THEN** the presentations the check reports out of date are those the impact listed

Pinned by: nothing yet.
