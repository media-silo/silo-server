<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Trials are listed, served by range, fetched again and deleted
`GET /v1/trials` SHALL answer 200 with every tried trial: its job, its recipe's ruleset, version and
the branch the version is on, its binding, its output's profile, and the encode's result, filtered by
`ruleset` and `branch` when they are given. `GET /v1/trials/{job}/file` SHALL serve the trial's output
as a presentation is served, whole and by range. `POST /v1/trials/{job}/fetch` SHALL clear an encoded
trial's failure, queue it on the queue the silo's own fetches are made from, and answer 202 with the
job before any of the fetch is made; a trial being fetched SHALL be answered 202 as it stands and
queued no second time, a `tried` trial SHALL be answered 200 with the job, and a trial in any other
state SHALL be 409. The client SHALL learn how the fetch ended from the job: `tried`, or `encoded` with
the failure recorded. `DELETE /v1/trials/{job}` SHALL delete the output and the job's
record, leaving its recipe committed, and answer 204. Fetching and deleting SHALL be the operator's.
For the file and the deletion a job that is not a tried trial SHALL be 404, and for the fetch a job
that is not a trial; a deletion of a trial the silo deleted, as its record of what it deleted holds,
SHALL be answered 204.

#### Scenario: a trial served and deleted
- **WHEN** a client asks for a tried trial's file with a range, and the operator then deletes the
  trial
- **THEN** the range is served as 206, and the trial is no longer listed

#### Scenario: a trial fetched again
- **WHEN** a trial's fetch failed, and the operator asks for it again once its node answers
- **THEN** the answer is 202 with the job, `encoded` with no failure, and the trial is then `tried`

#### Scenario: a fetch asked for twice
- **WHEN** the operator asks for a trial's fetch, and asks again while it is under way
- **THEN** both are answered 202, and the output is fetched once

#### Scenario: a trial deleted again
- **WHEN** the operator deletes a tried trial, and sends the same delete again
- **THEN** both answers are 204

Pinned by: `Tests/SiloTests/ServerTests.swift` (`yTrialsAreListedServedAndDeletedOverTheAPI`). A trial deleted again is pinned by the same and by `Tests/SiloTests/JobTests.swift` (`aTrialIsKeptApartFromTheLibraryAndNeverPlaced`). The fetch taken at once is pinned by nothing yet.
