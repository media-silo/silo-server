<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: Trials are listed, served by range, and deleted
`GET /v1/trials` SHALL answer 200 with every tried trial: its job, its recipe's ruleset, version and
the branch the version is on, its binding, its output's profile, and the encode's result, filtered by
`ruleset` and `branch` when they are given. `GET /v1/trials/{job}/file` SHALL serve the trial's output
as a presentation is served, whole and by range. `DELETE /v1/trials/{job}` SHALL delete the output and
the job's record, leaving its recipe committed, and answer 204, and SHALL be the operator's. A job that
is not a tried trial SHALL be 404.

#### Scenario: a trial served and deleted
- **WHEN** a client asks for a tried trial's file with a range, and the operator then deletes the
  trial
- **THEN** the range is served as 206, and the trial is no longer listed

Pinned by: nothing yet.
