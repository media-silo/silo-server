<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Jobs

## Purpose

A job is the run of one committed recipe. It is made from a draft recipe, which it commits, and it
records only the run: the recipe by id, its state, its attempts, where the output is, and the
placement that put it in the library. What the job reads is a [source](../sources/spec.md), what it
becomes is a [binding](../bindings/spec.md), and how is the [recipe](../recipes/spec.md); a claim
hands the node the recipe and each of the binding's segments, and placement builds the presentation
from the binding. This spec covers the record and the states it moves through, the routes the
operator's side and the nodes speak, the lease that notices a vanished node, placement, and the
operator's `silo-ctl jobs`. Serving and fetching the
files themselves is [file-serving](../file-serving/spec.md); the loop a node runs is
[worker](../worker/spec.md). Node records, approval and node tokens belong to the
[node-discovery](../node-discovery/spec.md) capability; this spec fixes only which gate each job
route sits behind, and that the operator's token passes both.

Rationale: [Silo proposal — Jobs, nodes and moving files](../../../Proposals/Silo.md) — the states table, and files moving once;
[Ingestion — Jobs](../../../Proposals/Ingestion.md) — a job is made from a recipe and is only the run.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: Jobs persist as one JSON file each under the state directory
The store SHALL keep one JSON file per job at `<state directory>/jobs/<id>.json`, written whole
and atomically on every change with ISO-8601 dates, load every such file once at start, and
thereafter hold the queue in memory — tens of records, not thousands. Every transition SHALL be a
read-modify-write of one job under one lock, and a claim's pick-and-lease SHALL be a single locked
step, so two transitions cannot cross.

#### Scenario: the queue survives a restart
- **WHEN** the silo stops and starts again over the same state directory
- **THEN** the queue it serves is the queue it had, states and attempts included

Pinned by: nothing yet.

### Requirement: The queue is read openly, oldest first, filtered by state
`GET /v1/jobs` SHALL answer every job, oldest first, with no token asked, and SHALL honour an
optional `?state=` query naming one job state. `GET /v1/jobs/{id}` SHALL answer the one job, or
404 for an id the silo does not know. Reading is one of the moments lapsed leases are reclaimed:
the answer reflects a node that has gone silent.

#### Scenario: the queue as a watcher sees it
- **WHEN** one job has been made and nothing else
- **THEN** `GET /v1/jobs?state=pending` lists its id, `GET /v1/jobs?state=placed` is `[]`, and
  `GET /v1/jobs/nothing` is 404

Pinned by: `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`).

### Requirement: Each job route sits behind the gate its audience holds
The two read routes SHALL ask no token. The routes the operator's side speaks — make, cancel, retry
and place — SHALL be behind the operator's configured bearer token, and a silo with no token
configured SHALL refuse them all. The four a node speaks — claim, progress, complete and fail — SHALL
be behind the node gate, which the operator's token also passes, so the embedded node and the
operator's own tooling need nothing more. The node gate and the node token it accepts are the
[node-discovery](../node-discovery/spec.md) capability's.

#### Scenario: the operator's token passes the node gate
- **WHEN** a client claims with `Authorization: Bearer <operator token>`
- **THEN** the claim is answered 200, as the embedded node's would be

Pinned by: `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`).

### Requirement: A claim leases the first pending job the node's ffmpeg can do
`POST /v1/jobs/claim` with the claiming node's id and its capabilities SHALL answer 200 with the
first `pending` job whose requirements are a subset of those capabilities — preferring a job of
whose every source the claimant holds a copy, then the oldest — or 200 with no job (`{}`) when
there is nothing it can do. A granted claim SHALL set the job `claimed`, append an attempt for the
node, clear any progress, and lease the job to the node for two minutes from the claim. The answer
SHALL carry the job's recipe and, for each of its binding's segments in order, one copy of the
segment's source — the claimant's own when it holds one — as a file reference whole, secret
included, and the segment's span in seconds: the claiming node is handed the secret it will fetch
by. Lapsed leases SHALL be reclaimed before an offer is made, so a job a vanished node held is
offered again.

#### Scenario: capabilities decide
- **WHEN** a job needs `["aac", "flac"]` and a node claiming with `["flac"]` asks, then one with
  `["flac", "aac"]`
- **THEN** the first answer has no job (`{}` over HTTP), the second holds the job `claimed` with
  the lease naming it and one attempt recorded, and a third claim by another node finds nothing

#### Scenario: a segment's span is handed over
- **WHEN** a node claims a job whose binding spans chapter 2 of a source whose chapters start at 0,
  1497.6 and 2995.2 seconds
- **THEN** the answer carries one segment: a copy of that source, secret included, from 1497.6 to
  2995.2 seconds

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromADraftToPlaced`, `aClaimPrefersWhatTheNodeHoldsAndHandsOverEachSpan`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`, which measures that the answer carries the recipe and the segment's copy, secret included).

### Requirement: A progress report is the heartbeat — the lease renews, the state answers
`POST /v1/jobs/{id}/progress` with the fraction, seconds, rate and speed the encoder reports
SHALL, on a `claimed` or `encoding` job, store the progress, make the job `encoding`, and extend
the lease to two minutes from the report. It SHALL answer the job's state. On a job in any other
state it SHALL change nothing and answer the state as it is — which is how a cancel reaches a
node. An unknown id SHALL be 404.

#### Scenario: the first report
- **WHEN** a node reports half done on a job it has just claimed
- **THEN** the job is `encoding`, the stored fraction is 0.5, and over HTTP the answer's body is
  `{"state":"encoding"}`

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromADraftToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`).

### Requirement: A lapsed lease loses the attempt, and the third loss fails the job
Whenever the queue is read or a claim is made, every `claimed` or `encoding` job whose lease has
expired SHALL have its open attempt ended as `lost`, its lease and progress cleared, and SHALL go
back to `pending` to be offered again — unless this was its third loss, when it SHALL become
`failed` with the failure `lost by 3 nodes`.

#### Scenario: a node vanishes, three times
- **WHEN** a claimed job's lease is put in the past and the queue is next read
- **THEN** the attempt's outcome is `lost` and the job is `pending`, and after the third such
  loss the job is `failed` with `lost by 3 nodes`

Pinned by: `Tests/SiloTests/JobTests.swift` (`aMismatchedLayoutFailsAndALapsedLeaseIsReclaimed`).

### Requirement: Completion encodes the job only when the reported layout matches the recipe
`POST /v1/jobs/{id}/complete` with the output's file reference — on the node that made it — and
the result SHALL be taken only from a `claimed` or `encoding` job; anything else is 409. The job
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

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromADraftToPlaced`, `aMismatchedLayoutFailsAndALapsedLeaseIsReclaimed`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`).

### Requirement: A node gives an active job up with a reason
`POST /v1/jobs/{id}/fail` with a reason SHALL be taken only from an active job — `claimed`,
`encoding` or `cancelling`; anything else is 409. The lease SHALL be cleared and the open attempt
ended, `failed` ordinarily and `cancelled` when a cancel was pending. An ordinary failure SHALL
make the job `failed` with the reason recorded; a failure that lands a pending cancel SHALL make
it `cancelled`.

#### Scenario: giving up
- **WHEN** a node fails the job it holds with the error it hit
- **THEN** the job is `failed` with that reason, the lease gone, the attempt's outcome `failed`

Pinned by: nothing yet (the service covers the cancel-landing half — `Tests/SiloTests/JobTests.swift`, `aJobGoesFromADraftToPlaced`).

### Requirement: Cancelling reaches a running job at its next progress report
`POST /v1/jobs/{id}/cancel` SHALL land a `pending`, `encoded` or `failed` job as `cancelled` at
once, lease cleared. On a `claimed` or `encoding` job it SHALL make the job `cancelling` and leave
the rest to the node: the job's state rides back in the answer to the node's next progress report,
and the node's fail report then lands the job `cancelled` with the attempt's outcome `cancelled`. A
job already `cancelling`, `cancelled`, `placing` or `placed` SHALL be 409.

#### Scenario: the node learns at its next report
- **WHEN** a job is cancelled while a node encodes it
- **THEN** the job is `cancelling`, the node's next progress report is answered `cancelling`, and
  the node's fail report makes it `cancelled` with the attempt's outcome `cancelled`

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromADraftToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`, for cancel on a placed job being 409).

### Requirement: A failed or cancelled job is offered again on retry
`POST /v1/jobs/{id}/retry` SHALL take only a `failed` or `cancelled` job; anything else is 409.
The job SHALL go back to `pending`, running the same committed recipe, with its attempts emptied and
its failure, lease, progress, output and result cleared.

#### Scenario: retrying after a cancel
- **WHEN** a cancelled job is retried
- **THEN** it is `pending` with no attempts, and claiming works again; a retry while a node is
  encoding is 409

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromADraftToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`).

### Requirement: Placement fetches the output from its holder and files it
`POST /v1/jobs/{id}/place` SHALL take only an `encoded` job with its output present; anything else
is 409, and a binding naming a library the silo no longer has is 404. The job SHALL become `placing`
while the silo works. The output SHALL be staged at `<library>/.silo/incoming/<job id>.<ext>`: moved
across when the output is a file URL — the embedded node's output is on this filesystem already —
and fetched over HTTP with the file's secret in `x-silo-secret` when it is remote, a non-200 answer
becoming 502 (`the node answered <status> for the output`). The presentation SHALL be built from the
binding of the job's recipe — its item, alternative, chapter names and source reference, its feature
map renumbered by the recipe's layout — in the profile of the recipe's output; the placement
computed and, when it would not apply, refused whole with its reasons as 409; otherwise applied and
the library re-scanned, so the index learns of the new presentation. The job SHALL then be `placed`
with a summary of the destination relative to the library root, the presentation's id, and the
writes made. Any failure along the way SHALL return the job to `encoded` with the failure recorded.

#### Scenario: an encoded job is placed
- **WHEN** the operator places an encoded job whose binding is part three of the serial *Pyramids of
  Mars*, in the series *Doctor Who (1963)* in library `main`, made by the unqualified output
- **THEN** the job is `placed` at `Doctor Who (1963)/Pyramids of Mars/Part Three.mkv`, the index
  answers its presentation id (and the media route serves it by range), and a second place is 409

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromADraftToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`), `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`, for the `- mobile` naming and the file moved out of the work folder).

### Requirement: The operator drives the queue with `silo-ctl jobs`
`silo-ctl jobs` SHALL offer `list` (oldest first, with `--state` to filter), `show` (one job,
whole, as JSON), `cancel`, `retry` and `place`, each naming the job by id. The silo SHALL be
reached by `--silo` or `SILO_URL` and the operator's token given by `--token` or `SILO_TOKEN`,
through the Foundation-only client. Each changing command SHALL print the job as one line: its
id, its state padded to ten, the percent done when encoding, `-> item (profile)` naming its
recipe's binding's item and its output's profile, `at destination` when placed, and `! failure`
when failed; `place` SHALL then print each of the placement's writes. A job keeps its recipe by
id, so the command SHALL fetch each recipe and each binding it names, a binding once.

#### Scenario: watching the queue
- **WHEN** the operator runs `SILO_URL=http://localhost:8742 SILO_TOKEN=secret silo-ctl jobs list`
- **THEN** the queue is printed oldest first, one line a job, or `no jobs`

Pinned by: nothing yet.

### Requirement: The job record carries one committed recipe's run
A job SHALL have an `id` (a lowercased UUID by default), a `state` of exactly one of `pending`,
`claimed`, `encoding`, `encoded`, `placing`, `placed`, `failed`, `cancelling` and `cancelled`,
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
- **WHEN** a job is made from a draft recipe
- **THEN** the job is `pending` with a lowercased UUID id, the recipe's id and its encoders, and no
  attempts, lease, progress, output, result, placement or failure

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromADraftToPlaced`), `Tests/SiloClientTests/SiloClientTests.swift` (`aJobIsMadeFromARecipeAndAClaimCarriesItsSegments`, for the record over the wire).

### Requirement: A job is made from a draft recipe whose sources can be had
`POST /v1/jobs` with a recipe's id, behind the operator's token, SHALL commit the recipe, make the job
`pending` with the recipe's encoders sorted as its requirements, and answer 201 with it. It SHALL be
404 for a recipe the silo does not have; 409 for a committed recipe, so one recipe is run by one job;
and 409 naming the source when a source of the recipe's binding has no copy, since no node could
fetch it. A job SHALL NOT be made any other way.

#### Scenario: a job from a draft
- **WHEN** the operator makes a job from a draft recipe whose source has a copy
- **THEN** the answer is 201 with a `pending` job, and the recipe is committed

#### Scenario: a second job from one recipe
- **WHEN** the operator makes a job from a recipe a job has already been made from
- **THEN** the answer is 409, and no job is made

#### Scenario: a source no node holds
- **WHEN** the operator makes a job from a draft whose binding's only source has no copy
- **THEN** the answer is 409 naming the source, and the recipe stays a draft

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobIsMadeOnlyFromADraftWhoseSourcesCanBeHad`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`).
