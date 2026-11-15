<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A ruleset's branches are listed, started, stored on and promoted
`GET /v1/rulesets/{name}/branches` SHALL answer 200 with each branch of the ruleset — its name,
its base, its head, the standard version it is up to date with, and whether it is closed — the
standard first. `POST /v1/rulesets/{name}/branches` with a branch name and a standard version SHALL
start a branch from that version and answer 201. A branch of that name started from that version SHALL
be answered 200 with the branch as it stands, so that a start sent again is answered as the first was;
a name taken in the ruleset by a branch from another version is 409, and a version not on the standard
is 400. `PUT /v1/rulesets/{name}` SHALL accept a `branch`, storing on that
branch, and an `upToDateWith`, the standard version the stored document takes in; a closed branch is
409. `POST /v1/rulesets/{name}/branches/{branch}/promote` SHALL promote the branch and answer 201
with the standard's new version, or 409 with a `Problem` naming the standard versions the branch has
not taken in; a branch its promotion has closed SHALL be answered 200 with the standard version that
promotion made. Every route here that changes something is the operator's. A ruleset or branch the
silo does not hold is 404.

#### Scenario: a branch is started, stored on and promoted
- **WHEN** the operator starts `trial` from `household@7`, puts a document on it, and promotes it
  while the standard's head is 7
- **THEN** the answers are 201, 201 with version 8, and 201 with version 9, and the branch list
  shows `trial` closed

#### Scenario: a promotion that would lose the standard's work
- **WHEN** the standard gained version 9 after `trial` was started from 7, and the operator
  promotes `trial`
- **THEN** the answer is 409 naming version 9, and the standard's head is still 9

#### Scenario: a branch started again
- **WHEN** the operator starts `trial` from `household@7`, sends the same request again, and then
  starts `trial` from `household@6`
- **THEN** the answers are 201, 200 with the same branch, and 409

#### Scenario: a promotion sent again
- **WHEN** `trial` is promoted as version 9, and the promotion is sent again
- **THEN** the second answer is 200 with version 9, and nothing is stored

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aBranchIsStartedStoredOnAndPromoted`). A start and a promotion sent again are pinned by nothing yet.
