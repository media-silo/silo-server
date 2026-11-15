<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Every store is a new version the silo numbers, and a version is never rewritten
A store of a document whose bytes are those of the head of the branch it is stored on SHALL make no
version, and SHALL be answered as that head, decided under the lock versions are numbered under; while
a branch has no version of its own, its head is its base. Any other store SHALL be given the next
version of its name — the latest plus one across every branch of
the ruleset, or 1 for a new name — chosen and written under one lock, so no two stores receive the
same number and `name@version` names exactly one document whichever branch it is on. Each version
SHALL record its branch and its parent: the previous version on its branch, or the branch's base
for a branch's first version. A version SHALL NOT be rewritten: a file already on disk under the
number chosen is refused as already there. A document SHALL be read before it is stored, and a
document the reader refuses SHALL NOT be stored. A name that is empty, contains a `/`, or begins
with a `.` SHALL be refused. There is no way to delete, rename or replace a version: a recipe names
the version it was resolved against, and that version must still say what it said.

#### Scenario: two stores are numbered in order
- **WHEN** a document is stored as `household`, and then another
- **THEN** the first store is version 1, the second version 2, and the latest version of
  `household` is 2, both on the standard, and version 2's parent is version 1

#### Scenario: a document that is not a ruleset is not stored
- **WHEN** a document testing `<when fact="nope" is="1"/>` is stored
- **THEN** it is refused with `"nope" is not a fact a rule can test`, and no version is added

#### Scenario: a name a ruleset cannot have
- **WHEN** a document is stored as `.hidden`
- **THEN** it is refused, and nothing is written

#### Scenario: branches share the sequence
- **WHEN** `household` is at version 7 on the standard, a branch is started from version 7 and a
  document is stored on it, and then a document is stored on the standard
- **THEN** the branch's version is 8 with parent 7, and the standard's is 9 with parent 7

#### Scenario: the head's document stored again
- **WHEN** `household` is at version 4 on the standard, and version 4's document is stored on the
  standard again
- **THEN** the store is answered as version 4, and the latest version of `household` is still 4

Pinned by: `Tests/SiloTests/ServerTests.swift` (`rulesetsAreVersionedAndTheOperatorGateHolds`), `Tests/SiloStoreTests/RulesetBranchTests.swift` (`branchesShareTheSequenceAndEachVersionNamesItsParent`).
The name and already-there refusals are pinned by nothing yet, and so is the head's document stored again.
