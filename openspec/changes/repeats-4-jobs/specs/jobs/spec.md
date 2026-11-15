<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A job is made from a resolved recipe whose sources can be had
`POST /v1/jobs` with a recipe's id, behind the operator's token, SHALL commit the recipe, make the job
`pending` with the recipe's encoders sorted as its requirements, and answer 201 with it; with
`trial`, the job SHALL be a trial job. It SHALL be
404 for a recipe the silo does not have; and 409 naming the source when a source of the recipe's
binding has no copy, since no node could fetch it. One recipe SHALL be run by one job: a request for a
committed recipe whose job the silo holds, trial or not as the request asks, SHALL be answered 200 with
that job as it stands, so that a request sent again is answered with the job the first made; one asking
for the other kind SHALL be 409 naming the job; and a committed recipe whose job the silo no longer
holds SHALL be 409 saying so. Two requests for one recipe sent at once SHALL make one job, and both
SHALL be answered with it. A job SHALL NOT be made any other way.

#### Scenario: a job from a resolved recipe
- **WHEN** the operator makes a job from a resolved recipe whose source has a copy
- **THEN** the answer is 201 with a `pending` job, and the recipe is committed

#### Scenario: a second job from one recipe
- **WHEN** the operator makes a job from a recipe a job has already been made from, and the job has
  since been claimed
- **THEN** the answer is 200 with the job made first, `claimed`, and no job is made

#### Scenario: a source no node holds
- **WHEN** the operator makes a job from a resolved recipe whose binding's only source has no copy
- **THEN** the answer is 409 naming the source, and the recipe stays resolved

#### Scenario: a trial from a branch's recipe
- **WHEN** the operator makes a trial job from a resolved recipe made by a version on a branch
- **THEN** the answer is 201 with a `pending` trial job, and the recipe is committed

#### Scenario: a trial asked for as a job
- **WHEN** the operator makes a trial job from a recipe, and then asks for a job that is not a trial
  from the same recipe
- **THEN** the second answer is 409 naming the trial job, and no job is made

#### Scenario: a recipe whose job is gone
- **WHEN** a trial job made from a recipe has been deleted, and the operator makes a trial job from the
  recipe
- **THEN** the answer is 409 saying the recipe's job is gone, and no job is made

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobIsMadeOnlyFromAResolvedRecipeWhoseSourcesCanBeHad`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`). `Tests/SiloTests/JobTests.swift` (`aTrialIsKeptApartFromTheLibraryAndNeverPlaced`), `Tests/SiloTests/ServerTests.swift` (`yTrialsAreListedServedAndDeletedOverTheAPI`), for a trial.
A request for a committed recipe's job answered with it, or refused naming it, is pinned by nothing yet.

### Requirement: Cancelling reaches a running job at its next progress report
`POST /v1/jobs/{id}/cancel` SHALL land a `pending`, `encoded` or `failed` job as `cancelled` at
once, lease cleared. On a `claimed` or `encoding` job it SHALL make the job `cancelling` and leave
the rest to the node: the job's state rides back in the answer to the node's next progress report,
and the node's fail report then lands the job `cancelled` with the attempt's outcome `cancelled`. A
job already `cancelling` or `cancelled` SHALL be answered 200 as it stands, changing nothing, so that a
cancel sent again is answered as the first was; one `placing`, `placed` or `tried` SHALL be 409.

#### Scenario: the node learns at its next report
- **WHEN** a job is cancelled while a node encodes it
- **THEN** the job is `cancelling`, the node's next progress report is answered `cancelling`, and
  the node's fail report makes it `cancelled` with the attempt's outcome `cancelled`

#### Scenario: a cancel sent again
- **WHEN** a pending job is cancelled, and the cancel is sent again
- **THEN** both answers are 200 with the job `cancelled`

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromResolvedToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`, for cancel on a placed job being 409). A cancel sent again is pinned by nothing yet.

### Requirement: A failed or cancelled job is offered again on retry
`POST /v1/jobs/{id}/retry` SHALL take a `failed` or `cancelled` job. A `pending` job SHALL be answered
200 as it stands, changing nothing, so that a retry sent again is answered as the first was; anything
else is 409 naming the job's state, since a job a node has claimed since cannot be told from one that
was never retried.
The job SHALL go back to `pending`, running the same committed recipe, with its attempts emptied and
its failure, lease, progress, output and result cleared.

#### Scenario: retrying after a cancel
- **WHEN** a cancelled job is retried
- **THEN** it is `pending` with no attempts, and claiming works again; a retry while a node is
  encoding is 409

#### Scenario: a retry sent again
- **WHEN** a failed job is retried, and the retry is sent again before a node claims it
- **THEN** both answers are 200 with the job `pending`

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromResolvedToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`). A retry sent again is pinned by nothing yet.

### Requirement: Placement fetches the output from its holder and files it
`POST /v1/jobs/{id}/place` SHALL take an `encoded` job with its output present. A `placed` job SHALL be
answered 200 as it stands, its placement summary included, so that a place sent again is answered as
the first was; anything else is 409, a `placing` job among them, since how its placement ends is not
yet known; and a binding naming a library the silo no longer has is 404. The job SHALL become `placing`
while the silo works. The output SHALL be staged at `<library>/.silo/incoming/<job id>.<ext>`: moved
across when the output is a file URL — the embedded node's output is on this filesystem already —
and fetched over HTTP with the file's secret in `x-silo-secret` when it is remote, a non-200 answer
becoming 502 (`the node answered <status> for the output`). The presentation SHALL be built from the
binding of the job's recipe — its item, alternative and chapter names, its feature map renumbered by
the recipe's layout — in the profile of the recipe's output, with its provenance: a `<source>` naming
the binding and holding one `<segment>` per segment in order, each its source's natural key when it
has one and its chapter span when it has one, and a `<transform>` holding the recipe's stack, its
ruleset and version and a `<layer>` for each layer above it with its version and digest; the placement
computed and, when it would not apply, refused whole with its reasons as 409; otherwise applied, and
each sidecar it wrote re-read into the index, as [index](../index/spec.md) sets out, so the index
learns of the new presentation without the library being walked. The job SHALL then be `placed`
with a summary of the destination relative to the library root, the presentation's id, and the
writes made. Any failure along the way SHALL return the job to `encoded` with the failure recorded.

#### Scenario: an encoded job is placed
- **WHEN** the operator places an encoded job whose binding is part three of the serial *Pyramids of
  Mars*, in the series *Doctor Who (1963)* in library `main`, made by the unqualified output
- **THEN** the job is `placed` at `Doctor Who (1963)/01 - Pyramids of Mars/Part Three.mkv`, the index
  answers its presentation id (and the media route serves it by range), the serial's sidecar names
  the binding and the recipe's ruleset version on the presentation, and a second place is answered 200
  with the job, `placed`, writing nothing

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromResolvedToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`), `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`, for the `- mobile` naming and the file moved out of the work folder). `Tests/SiloTests/StackTests.swift` (`aPlacedPresentationRecordsItsBindingAndTheRulesThatMadeIt`, for the presentation's provenance). A second place answered with the job is pinned by nothing yet.

### Requirement: Completion encodes the job only when the reported layout matches the recipe
`POST /v1/jobs/{id}/complete` with the output's file reference — on the node that made it — and
the result SHALL be taken from a `claimed` or `encoding` job. A job that already holds that output and
that result, `encoded` or `failed` as the result made it, SHALL be answered 200 as it stands, changing
nothing, and a trial SHALL be queued for fetching once, so that a completion sent again is answered as
the first was; anything else is 409. The job
SHALL record the output and the result (its size and its probed stream list), clear the lease and
set progress to done. The open attempt SHALL end `encoded` when the reported layout matched the
recipe and `failed` when it did not. A match SHALL make the job `encoded`; a mismatch SHALL make
it `failed` with the failure `the output's layout is not the recipe's`.

#### Scenario: a matching layout
- **WHEN** a node completes its encoding job with an output and `layoutMatched` true
- **THEN** the job is `encoded` and the attempt's outcome is `encoded`

#### Scenario: a mismatched layout
- **WHEN** a node completes with `layoutMatched` false
- **THEN** the job is `failed` with `the output's layout is not the recipe's`, and placing it is
  refused

#### Scenario: a completion sent again
- **WHEN** a node completes its job with an output and `layoutMatched` true, and sends the same
  completion again
- **THEN** both answers are 200 with the job `encoded`, and it has one attempt

#### Scenario: a completion of another output
- **WHEN** an encoded job is completed again with another output
- **THEN** the answer is 409, and the job holds the first output

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromResolvedToPlaced`, `aMismatchedLayoutFailsAndALapsedLeaseIsReclaimed`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`). A completion sent again is pinned by nothing yet.

### Requirement: A node gives an active job up with a reason
`POST /v1/jobs/{id}/fail` with a reason SHALL be taken from an active job — `claimed`,
`encoding` or `cancelling`. A job `failed` with that reason, or `cancelled`, SHALL be answered 200 as it
stands, changing nothing, so that a failure sent again is answered as the first was; anything else is
409. The lease SHALL be cleared and the open attempt
ended, `failed` ordinarily and `cancelled` when a cancel was pending. An ordinary failure SHALL
make the job `failed` with the reason recorded; a failure that lands a pending cancel SHALL make
it `cancelled`.

#### Scenario: giving up
- **WHEN** a node fails the job it holds with the error it hit
- **THEN** the job is `failed` with that reason, the lease gone, the attempt's outcome `failed`

#### Scenario: a failure sent again
- **WHEN** a node fails the job it holds, and sends the same failure again
- **THEN** both answers are 200 with the job `failed` with that reason, and it has one attempt

Pinned by: nothing yet (the service covers the cancel-landing half — `Tests/SiloTests/JobTests.swift`, `aJobGoesFromResolvedToPlaced`).

### Requirement: A job's state is checked and changed in one step
Every change of a job's state — a cancel, a retry, a progress report, a completion, a failure and
the start of a placement — SHALL check the state it changes and write the change in one step
under the job store's lock, so that two copies of one request sent at once, as a client retrying a
request whose first copy still runs sends them, cannot both pass the check. The copy that finds
the state the other made SHALL be answered as made, as a request sent again is; one that finds
another state SHALL be refused as the wrong state; and a progress report SHALL leave a job that is no
longer being encoded as it found it.

#### Scenario: a completion and a failure sent at once
- **WHEN** a claimed job is completed and failed at the same moment
- **THEN** exactly one of the two is made, and the other is refused as the wrong state

#### Scenario: a report sent as the job is cancelled
- **WHEN** a claimed job is cancelled while a progress report for it arrives
- **THEN** the job is `cancelling` afterwards, for the node's next report to learn of

#### Scenario: one completion sent twice at once
- **WHEN** a claimed job's completion is sent twice at the same moment
- **THEN** the job is completed once, with one attempt, and both are answered 200 with it

Pinned by: `Tests/SiloTests/JobTests.swift` (`twoChangesOfOneJobSentAtOnceAreNeverBothMade`,
`aReportSentAsAJobIsCancelledNeverUndoesTheCancel`). One completion sent twice at once is pinned by nothing yet.
