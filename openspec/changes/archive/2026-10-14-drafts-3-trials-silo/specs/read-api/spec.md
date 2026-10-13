<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: Trials are listed, served by range, fetched again and deleted
`GET /v1/trials` SHALL answer 200 with every tried trial: its job, its recipe's ruleset, version and
the branch the version is on, its binding, its output's profile, and the encode's result, filtered by
`ruleset` and `branch` when they are given. `GET /v1/trials/{job}/file` SHALL serve the trial's output
as a presentation is served, whole and by range. `POST /v1/trials/{job}/fetch` SHALL fetch an encoded
trial's output again and answer the job, 409 for a trial that is not encoded and 502 when the node
holding the output does not give it. `DELETE /v1/trials/{job}` SHALL delete the output and the job's
record, leaving its recipe committed, and answer 204. Fetching and deleting SHALL be the operator's.
For the file and the deletion a job that is not a tried trial SHALL be 404, and for the fetch a job
that is not a trial.

#### Scenario: a trial served and deleted
- **WHEN** a client asks for a tried trial's file with a range, and the operator then deletes the
  trial
- **THEN** the range is served as 206, and the trial is no longer listed

Pinned by: `Tests/SiloTests/ServerTests.swift` (`yTrialsAreListedServedAndDeletedOverTheAPI`).
