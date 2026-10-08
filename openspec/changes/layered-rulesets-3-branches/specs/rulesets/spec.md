<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Every store is a new version the silo numbers, and a version is never rewritten
A store SHALL be given the next version of its name — the latest plus one across every branch of
the ruleset, or 1 for a new name — chosen and written under one lock, so no two stores receive the
same number and `name@version` names exactly one document whichever branch it is on. Each version
SHALL record its branch and its parent: the previous version on its branch, or the branch's base
for a branch's first version. A version SHALL NOT be rewritten: a file already on disk under the
number chosen is refused as already there. A document SHALL be read before it is stored, and a
document the reader refuses SHALL NOT be stored. A name that is empty, contains a `/`, or begins
with a `.` SHALL be refused. There is no way to delete, rename or replace a version: a recipe names
the version it was resolved against, and that version must still say what it said.

#### Scenario: two stores are numbered in order
- **WHEN** the same document is stored as `household` twice
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

Pinned by: `Tests/SiloTests/ServerTests.swift` (`rulesetsAreVersionedAndTheOperatorGateHolds`).
The name and already-there refusals, and branches, are pinned by nothing yet.

## ADDED Requirements

### Requirement: A ruleset has a standard and branches
Every ruleset SHALL have a branch named `standard`, and every version stored without naming a
branch SHALL be on it. A branch SHALL be started from a version of the standard, its base, under a
name unique within the ruleset that is not `standard` and follows a ruleset name's rules; it SHALL
hold versions of its own, and its head is its latest version, or its base while it has none. A
branch SHALL record the standard version it is up to date with, which starts as its base and moves
only when a version stored on the branch declares a later one.

#### Scenario: a store with no branch
- **WHEN** a document is stored as `household` naming no branch
- **THEN** it is the standard's next version

#### Scenario: a new branch before any store
- **WHEN** a branch `trial` is started from `household@7`
- **THEN** its head is `household@7` and it is up to date with version 7

Pinned by: nothing yet.

### Requirement: Promotion makes a branch's head the standard's next version, and never merges
Promoting a branch SHALL store its head's document as the standard's next version, its parent the
standard's head and recording the branch head it came from, and SHALL close the branch: a closed
branch takes no store and no application. Promotion SHALL be refused, naming the versions, when the
standard has versions later than the one the branch is up to date with, and SHALL store nothing;
the branch is brought up to date by storing a version on it that declares the standard's head.

#### Scenario: a promotion over the standard's head
- **WHEN** branch `trial`, started from version 7 and holding version 8, is promoted while the
  standard's head is 7
- **THEN** version 9 is stored on the standard with version 8's document, parent 7, promoted from
  8, and `trial` is closed

#### Scenario: the standard moved on
- **WHEN** the standard gained version 9 after `trial` was started from version 7, and `trial` is
  promoted
- **THEN** the promotion is refused naming version 9, and nothing is stored

#### Scenario: brought up to date
- **WHEN** `trial` is refused for not taking in version 9, a document is stored on it declaring that
  it is up to date with version 9, and `trial` is promoted again
- **THEN** the standard's next version is stored with that document, and `trial` is closed

Pinned by: nothing yet.
