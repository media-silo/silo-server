<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A trial is kept apart from the library, and never placed
When a trial job is encoded, the silo SHALL fetch its output, as placement fetches one, into
`trials/<job id>.<ext>` in its state directory, and the job SHALL become `tried`. A fetch that fails
SHALL leave the job `encoded` with the failure recorded, and the silo SHALL fetch it again when the
operator asks. The node that reported the job complete SHALL NOT wait on the fetch. Placing a trial
job SHALL be refused with 409, saying a trial is never placed, and the background check SHALL never
check a trial.

#### Scenario: a trial encoded
- **WHEN** a trial job is claimed, encoded and reported complete
- **THEN** its output is in the trial area, the job is `tried`, and placing it is 409

#### Scenario: a node gone before the fetch
- **WHEN** a trial job is reported complete by a node that no longer answers at its address
- **THEN** the job stays `encoded` with the failed fetch recorded, and once the output can be had,
  asking again makes it `tried`

Pinned by: `Tests/SiloTests/JobTests.swift` (`aTrialIsKeptApartFromTheLibraryAndNeverPlaced`,
`aTrialWhoseFetchFailsStaysEncodedToBeFetchedAgain`).

## MODIFIED Requirements

### Requirement: The job record carries one committed recipe's run
A job SHALL have an `id` (a lowercased UUID by default), a `state` of exactly one of `pending`,
`claimed`, `encoding`, `encoded`, `placing`, `placed`, `tried`, `failed`, `cancelling` and `cancelled`,
whether it is a `trial` — a record that does not say is not one —
`createdAt` and `updatedAt` timestamps (`updatedAt` refreshed on every change), the `recipe` it runs
by id, the `requirements` (the encoders the recipe needs), the `attempts`, the current `lease`, the
latest `progress`, the `output` file reference, the `result`, the `placement` summary, and the
`failure` reason. A file reference SHALL carry its `holder` (the node the file is on), its `url`, the
holder's own `path` for opening locally, its `sizeBytes`, and the `secret` that guards it. An attempt
SHALL record its node, when it started and ended, and an outcome of `lost`, `failed`, `cancelled` or
`encoded`. A lease SHALL name a node and when it expires. A job is *active* in exactly the states
`claimed`, `encoding` and `cancelling`. A job's *sources* are the sources of its recipe's binding's
segments, and where a requirement speaks of a job's source it means each of them.

#### Scenario: a job freshly made
- **WHEN** a job is made from a resolved recipe
- **THEN** the job is `pending` with a lowercased UUID id, the recipe's id and its encoders, and no
  attempts, lease, progress, output, result, placement or failure

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromResolvedToPlaced`), `Tests/SiloClientTests/SiloClientTests.swift` (`aJobIsMadeFromARecipeAndAClaimCarriesItsSegments`, for the record over the wire). `Tests/SiloTests/JobTests.swift` (`aTrialIsKeptApartFromTheLibraryAndNeverPlaced`, for a trial's record).

### Requirement: A job is made from a resolved recipe whose sources can be had
`POST /v1/jobs` with a recipe's id, behind the operator's token, SHALL commit the recipe, make the job
`pending` with the recipe's encoders sorted as its requirements, and answer 201 with it; with
`trial`, the job SHALL be a trial job. It SHALL be
404 for a recipe the silo does not have; 409 for a committed recipe, so one recipe is run by one job;
and 409 naming the source when a source of the recipe's binding has no copy, since no node could
fetch it. A job SHALL NOT be made any other way.

#### Scenario: a job from a resolved recipe
- **WHEN** the operator makes a job from a resolved recipe whose source has a copy
- **THEN** the answer is 201 with a `pending` job, and the recipe is committed

#### Scenario: a second job from one recipe
- **WHEN** the operator makes a job from a recipe a job has already been made from
- **THEN** the answer is 409, and no job is made

#### Scenario: a source no node holds
- **WHEN** the operator makes a job from a resolved recipe whose binding's only source has no copy
- **THEN** the answer is 409 naming the source, and the recipe stays resolved

#### Scenario: a trial from a branch's recipe
- **WHEN** the operator makes a trial job from a resolved recipe made by a version on a branch
- **THEN** the answer is 201 with a `pending` trial job, and the recipe is committed

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobIsMadeOnlyFromAResolvedRecipeWhoseSourcesCanBeHad`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`). `Tests/SiloTests/JobTests.swift` (`aTrialIsKeptApartFromTheLibraryAndNeverPlaced`), `Tests/SiloTests/ServerTests.swift` (`yTrialsAreListedServedAndDeletedOverTheAPI`), for a trial.
