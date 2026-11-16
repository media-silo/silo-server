<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Every ruleset store is a new version, and is the operator's
`PUT /v1/rulesets/{name}` with a JSON `RulesetDocument` SHALL store the `document` as the next version
of the name — on the standard, or on the `branch` the body names — and answer 201 with the version the
silo assigned; a `version` in the body SHALL be ignored on a store, since numbering is the silo's. A
document the ruleset reader refuses SHALL NOT be stored, and the answer SHALL be 400 with a `Problem`
whose `detail` says why. A document whose bytes are those of the head of the branch it is stored to
SHALL be answered 200 with that head's version, storing nothing, whatever its `basedOn`, so that a store
sent again is answered with the version the first made. Otherwise the body SHALL carry `basedOn`, the
head of the branch it is stored to that the document was made from, or zero for a name that must be
new, when the name has a version; a store without it to a name that has one SHALL be 400 and store
nothing, and a store to a new name MAY leave it out. The store SHALL go ahead only if `basedOn` is
still the head, decided under the lock the version number is taken under, and otherwise SHALL
store nothing and answer 409 with a `Problem` naming the head. The route is the operator's.

#### Scenario: two stores are numbered in order
- **WHEN** the operator puts the household ruleset at `/v1/rulesets/household`, and then another
  document based on version 1
- **THEN** the answers are 201 with `version` 1 and then 2

#### Scenario: a document that is not a ruleset is refused
- **WHEN** the operator puts a document testing `<when fact="nope" is="1"/>`
- **THEN** the answer is 400 with `not a fact a rule can test` in the problem
  detail, and nothing is stored

#### Scenario: two editors from one base
- **WHEN** two stores of different documents to the standard are each based on version 3, the
  standard's head
- **THEN** the first is 201 with version 4, and the second is 409 naming version 4 and stores nothing

#### Scenario: a new name, and one that is not new
- **WHEN** a store is based on zero for a name the silo has no version of, and another based on zero
  for `household`
- **THEN** the first is 201 with version 1, and the second is 409

#### Scenario: a store sent again
- **WHEN** a store based on version 3, the standard's head, is answered 201 with version 4, and the same
  request is sent again
- **THEN** the second answer is 200 with version 4, and nothing is stored

#### Scenario: a store that does not say its base
- **WHEN** a document other than its head's is put for `household`, which has a version, with no
  `basedOn`
- **THEN** the answer is 400, and nothing is stored

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`, `aRulesetIsReadWholeADraftCheckedAndAStoreBasedOnItsHead`).
