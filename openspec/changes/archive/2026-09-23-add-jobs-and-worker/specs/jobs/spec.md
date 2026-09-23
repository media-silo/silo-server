<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The job record carries the whole of a file's way to one presentation
A job SHALL have an `id` (a lowercased UUID by default), a `state` of exactly one of `unassigned`,
`pending`, `claimed`, `encoding`, `encoded`, `placing`, `placed`, `failed`, `cancelling`,
`cancelled`, `createdAt` and `updatedAt` timestamps (`updatedAt` refreshed on every change), a
`source` file reference, an optional `discName`, the `probe` of the source the tool sent, the
optional `makeMKV` facts, and then everything the queue learns: the `assignment`, the merged
`facts`, the resolved `recipe`, the `requirements` (the encoders the recipe needs), the `attempts`,
the current `lease`, the latest `progress`, the `output` file reference, the `result`, the
`placement` summary, and the `failure` reason. A file reference SHALL carry its `holder` (the node
the file is on), its `url`, the holder's own `path` for opening locally, its `sizeBytes`, and the
`secret` that guards it. An attempt SHALL record its node, when it started and ended, and an
outcome of `lost`, `failed`, `cancelled` or `encoded`. A lease SHALL name a node and when it
expires. A job is *active* in exactly the states `claimed`, `encoding` and `cancelling`.

#### Scenario: a freshly registered rip
- **WHEN** the tool registers a rip with its source, disc name and probe
- **THEN** the job is `unassigned` with a lowercased UUID id, the source as given, and no
  assignment, facts, recipe, requirements, attempts, lease, progress, output, result, placement
  or failure

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`).

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
- **WHEN** one rip has been registered and nothing else
- **THEN** `GET /v1/jobs?state=unassigned` lists its id, `GET /v1/jobs?state=placed` is `[]`, and
  `GET /v1/jobs/nothing` is 404

Pinned by: `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`).

### Requirement: The tool registers a rip the moment it finishes
`POST /v1/jobs` with a body of the source file reference, an optional disc name, the probe the
tool ran with `ffprobe` (so the silo needs none of its own to resolve a recipe), and MakeMKV's
facts SHALL create the job as `unassigned` and answer 201 with it. The route SHALL be behind the
operator's token: a request without it gets 401.

#### Scenario: registration over HTTP
- **WHEN** a client posts a rip to `/v1/jobs` without a token, then again with
  `Authorization: Bearer <operator token>`
- **THEN** the first answer is 401 and the second is 201 with the job, `unassigned`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`).

### Requirement: Each job route sits behind the operator's token
The two read routes SHALL ask no token. Every route that changes the queue — register, assign,
claim, progress, complete, fail, cancel, retry and place — SHALL be behind the operator's
configured bearer token, and a silo with no token configured SHALL refuse them all. The embedded
node asks the job service in process, so it needs no token of its own; a node's own token, and
the gate the working routes move behind, arrive with the nodes change.

#### Scenario: a claim without the token
- **WHEN** a client posts to `/v1/jobs/claim` with no `Authorization` header
- **THEN** the answer is 401

#### Scenario: a claim carries the operator's token
- **WHEN** a client claims with `Authorization: Bearer <operator token>`
- **THEN** the claim is answered 200

Pinned by: `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`).

### Requirement: An assignment lands the job pending, facts merged and recipe resolved
`PUT /v1/jobs/{id}/assignment` SHALL take an assignment — the library, the item's container
lineage as repository documents, the item, the optional alternative and profile, the feature map,
the chapters, and the ruleset by name with an optional version — and SHALL refuse, before any
resolution, with 404 for an unknown job; 409 for a job not `unassigned`, `pending` or `failed`;
and 400 with the reason when the job carries no probe, the library is unknown to the silo, the
ruleset version does not exist, a container document cannot be read, the item is not in the last
container, or the feature map names a feature that container does not have. An audio stream a
feature is mapped to SHALL take its role from that feature: `commentary` for a commentary,
`isolatedMusic` for isolated music, `other` otherwise. Facts SHALL then be merged from the probe,
the MakeMKV facts and the assignment, and the recipe resolved against the stored ruleset — its
latest version unless the assignment names one. A stream no rule decides SHALL be 422, the
resolver's report as given. On success the job SHALL become `pending` with the assignment stored
naming the ruleset version actually resolved, the facts and recipe recorded, the `requirements`
set to the recipe's encoders sorted, and any failure, lease and progress cleared.

#### Scenario: the household ruleset against an episode
- **WHEN** the rip of an episode with a main mix and a mapped commentary is assigned against the
  `household` ruleset
- **THEN** the job is `pending`, its audio roles are `[.main, .commentary]` (the feature map
  decides; the stream's title alone is only a hint), its requirements are `["aac", "flac"]`, and
  its stored assignment names ruleset version 1

#### Scenario: a stream no rule decides
- **WHEN** the same job is assigned against a ruleset that decides no audio
- **THEN** the answer is 422

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`).

### Requirement: A claim leases the first pending job the node's ffmpeg can do
`POST /v1/jobs/claim` with the claiming node's id and its capabilities SHALL answer 200 with the
first `pending` job whose requirements are a subset of those capabilities — preferring a job whose
source the claimant already holds, then the oldest — or 200 with no job (`{}`) when there is
nothing it can do. A granted claim SHALL set the job `claimed`, append an attempt for the node,
clear any progress, and lease the job to the node for two minutes from the claim. The answer
carries the source file reference whole, secret included: the claiming node is handed the secret
it will fetch by. Lapsed leases SHALL be reclaimed before an offer is made, so a job a vanished
node held is offered again.

#### Scenario: capabilities decide
- **WHEN** a job needs `["aac", "flac"]` and a node claiming with `["flac"]` asks, then one with
  `["flac", "aac"]`
- **THEN** the first answer has no job (`{}` over HTTP), the second holds the job `claimed` with
  the lease naming it and one attempt recorded, and a third claim by another node finds nothing

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`, which measures that the answer carries the source's secret). The prefer-what-you-hold ordering is pinned by nothing yet.

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

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`).

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

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`, `aMismatchedLayoutFailsAndALapsedLeaseIsReclaimed`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`).

### Requirement: A node gives an active job up with a reason
`POST /v1/jobs/{id}/fail` with a reason SHALL be taken only from an active job — `claimed`,
`encoding` or `cancelling`; anything else is 409. The lease SHALL be cleared and the open attempt
ended, `failed` ordinarily and `cancelled` when a cancel was pending. An ordinary failure SHALL
make the job `failed` with the reason recorded; a failure that lands a pending cancel SHALL make
it `cancelled`.

#### Scenario: giving up
- **WHEN** a node fails the job it holds with the error it hit
- **THEN** the job is `failed` with that reason, the lease gone, the attempt's outcome `failed`

Pinned by: nothing yet (the service covers the cancel-landing half — `Tests/SiloTests/JobTests.swift`, `aJobGoesFromRegisteredToPlaced`).

### Requirement: Cancelling reaches a running job at its next progress report
`POST /v1/jobs/{id}/cancel` SHALL land an `unassigned`, `pending`, `encoded` or `failed` job as
`cancelled` at once, lease cleared. On a `claimed` or `encoding` job it SHALL make the job
`cancelling` and leave the rest to the node: the job's state rides back in the answer to the
node's next progress report, and the node's fail report then lands the job `cancelled` with the
attempt's outcome `cancelled`. A job already `cancelling`, `cancelled`, `placing` or `placed`
SHALL be 409.

#### Scenario: the node learns at its next report
- **WHEN** a job is cancelled while a node encodes it
- **THEN** the job is `cancelling`, the node's next progress report is answered `cancelling`, and
  the node's fail report makes it `cancelled` with the attempt's outcome `cancelled`

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`, for cancel on a placed job being 409).

### Requirement: A failed or cancelled job is offered again on retry
`POST /v1/jobs/{id}/retry` SHALL take only a `failed` or `cancelled` job; anything else is 409.
The job SHALL go back to `pending` — or to `unassigned` when no recipe was ever resolved for it —
with its attempts emptied and its failure, lease, progress, output and result cleared.

#### Scenario: retrying after a cancel
- **WHEN** a cancelled job that was assigned is retried
- **THEN** it is `pending` with no attempts, and claiming works again; a retry while a node is
  encoding is 409

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`).

### Requirement: Placement fetches the output from its holder and files it
`POST /v1/jobs/{id}/place` SHALL take only an `encoded` job, with its output and assignment
present; anything else is 409, and an unknown library 404. The job SHALL become `placing` while
the silo works. The output SHALL be staged at `<library>/.silo/incoming/<job id>.<ext>`: moved
across when the output is a file URL — the embedded node's output is on this filesystem already —
and fetched over HTTP with the file's secret in `x-silo-secret` when it is remote, a non-200
answer becoming 502 (`the node answered <status> for the output`). The presentation SHALL be
built from the assignment, its tracks renumbered by the recipe, its chapters and source carried;
the placement computed and, when it would not apply, refused whole with its reasons as 409;
otherwise applied and the library re-scanned, so the index learns of the new presentation. The
job SHALL then be `placed` with a summary of the destination relative to the library root, the
presentation's id, and the writes made. Any failure along the way SHALL return the job to
`encoded` with the failure recorded.

#### Scenario: an encoded job is placed
- **WHEN** the operator places an encoded job into `main`
- **THEN** the job is `placed` at `Doctor Who (1963)/Pyramids of Mars/Part Three.mkv`, the index
  answers its presentation id (and the media route serves it by range), and a second place is 409

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`), `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`, for the `- mobile` naming and the file moved out of the work folder).

### Requirement: The operator drives the queue with `silo-ctl jobs`
`silo-ctl jobs` SHALL offer `list` (oldest first, with `--state` to filter), `show` (one job,
whole, as JSON), `cancel`, `retry` and `place`, each naming the job by id. The silo SHALL be
reached by `--silo` or `SILO_URL` and the operator's token given by `--token` or `SILO_TOKEN`,
through the Foundation-only client. Each changing command SHALL print the job as one line: its
id, its state padded to ten, the percent done when encoding, the source file's name, `-> item
(profile)` when assigned, `at destination` when placed, and `! failure` when failed; `place`
SHALL then print each of the placement's writes.

#### Scenario: watching the queue
- **WHEN** the operator runs `SILO_URL=http://localhost:8080 SILO_TOKEN=secret silo-ctl jobs list`
- **THEN** the queue is printed oldest first, one line a job, or `no jobs`

Pinned by: nothing yet.
