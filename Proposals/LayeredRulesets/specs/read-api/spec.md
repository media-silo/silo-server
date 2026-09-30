<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A ruleset's branches are listed, started, stored on and promoted
`GET /v1/rulesets/{name}/branches` SHALL answer 200 with each branch of the ruleset — its name,
its base, its head, the standard version it is up to date with, and whether it is closed — the
standard first. `POST /v1/rulesets/{name}/branches` with a branch name and a standard version SHALL
start a branch from that version and answer 201; a name taken in the ruleset is 409, and a version
not on the standard is 400. `PUT /v1/rulesets/{name}` SHALL accept a `branch`, storing on that
branch, and an `upToDateWith`, the standard version the stored document takes in; a closed branch is
409. `POST /v1/rulesets/{name}/branches/{branch}/promote` SHALL promote the branch and answer 201
with the standard's new version, or 409 with a `Problem` naming the standard versions the branch has
not taken in. Every route here that changes something is the operator's. A ruleset or branch the
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

Pinned by: nothing yet.

### Requirement: The out-of-date presentations of a library are read, and so is a promotion's impact
`GET /v1/libraries/{library}/out-of-date` SHALL answer 200 with the library's out-of-date
presentations — each with its container, item and file, the job that made it, the stack it was
made by, every stream that would change with what it got and what it would get, and its source
state — and the count of the library's presentations placed without a job.
`GET /v1/rulesets/{name}/branches/{branch}/impact` SHALL answer, in the same shape, the
presentations that promoting the branch would put out of date, changing nothing. A library, ruleset
or branch the silo does not hold is 404.

#### Scenario: a promotion's impact is its outcome
- **WHEN** a branch's impact is read and the branch is then promoted, with nothing else changing
- **THEN** the library's out-of-date presentations afterwards are those the impact listed

Pinned by: nothing yet.
