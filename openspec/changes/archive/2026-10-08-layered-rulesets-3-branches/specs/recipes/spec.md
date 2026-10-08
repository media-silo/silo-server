<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: An application may name a branch of its ruleset
An application SHALL accept a `branch` of the ruleset it applies, and SHALL then resolve against
the branch's head, or the version it names when that version is on the branch. With no branch named
it SHALL resolve against the standard's head, or the version named. A branch the ruleset does not
have, or a version not on the branch named, SHALL be 400, and a closed branch SHALL be 409; each
stores nothing. A recipe SHALL need no field for its branch: its version is on exactly one.

#### Scenario: a trial branch applied to one binding
- **WHEN** `household`'s standard head is version 7, its branch `trial` holds version 8, and
  `household` is applied to a binding naming the branch `trial`
- **THEN** the drafts name `household@8`, and an application to another binding naming no branch
  makes drafts naming `household@7`

#### Scenario: a closed branch
- **WHEN** an application names a branch that has been promoted
- **THEN** the answer is 409, and nothing is stored

Pinned by: `Tests/SiloTests/BranchApplicationTests.swift` (`anApplicationOnABranchTakesItsHead`).
