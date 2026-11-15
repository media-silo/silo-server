<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Promotion makes a branch's head the standard's next version, and never merges
Promoting a branch SHALL store its head's document as the standard's next version, its parent the
standard's head and recording the branch head it came from, and SHALL close the branch: a closed
branch takes no store and no application. Promoting a branch already closed by its promotion SHALL
store nothing, and SHALL answer the standard version recorded as promoted from the branch's head. Promotion SHALL be refused, naming the versions, when the
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

#### Scenario: promoted again
- **WHEN** `trial`, holding version 8, has been promoted as version 9, and is promoted again
- **THEN** the promotion answers version 9, and nothing is stored

Pinned by: `Tests/SiloStoreTests/RulesetBranchTests.swift` (`promotionIsAFastForwardRefusedOverWhatTheBranchHasNotTakenIn`, `aStraightPromotionOverTheStandardsHead`).
