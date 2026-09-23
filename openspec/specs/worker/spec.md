<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Worker

## Purpose

The worker is the node's work loop, run until it is stopped: claim a job — the silo preferring
one whose source the claiming node already holds — open the source locally or fetch it from its
holder by range, encode it as the recipe says, probe the output, check its layout against the
recipe (a mismatch fails the job), keep the silo posted — every progress report renews the lease,
so progress doubles as heartbeat, and a cancellation rides back in the answer — report completion
with where the output is, and serve the output so the silo can fetch it at placement. One worker
covers both shapes of node: `silo-node` on another machine, speaking the silo's API over HTTP,
and the node inside the silo itself. The job record and its states are [jobs](../jobs/spec.md);
the serving and fetching mechanics are [file-serving](../file-serving/spec.md).

Rationale: [Silo proposal — Jobs, nodes and moving files](../../../Proposals/Silo.md) — files move once, progress as heartbeat, and the node inside the silo.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: One loop does for a node on another machine and the node inside the silo
The loop SHALL be one `Worker`, an actor asking a `JobsAPI` — claim, report, complete, fail —
which SHALL have exactly two implementations: the silo's HTTP client, for a node on another
machine, and the silo's own job service, in process, for the embedded node. Only the `JobsAPI`
differs between the two shapes; the claiming, the source handling, the encode, the probing, the
checks and the reports SHALL be the same code path, so there is one loop to test.

#### Scenario: one code path, two wirings
- **WHEN** the worker's single-job pass is run against the job service directly, as the embedded
  node runs it
- **THEN** the job is claimed, encoded and reported complete exactly as a node on another machine
  would report it over HTTP

Pinned by: `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`).

### Requirement: SILO_EMBEDDED_NODE=true runs the loop inside the silo
When `SILO_EMBEDDED_NODE` is true — it defaults to false — the silo SHALL run a worker inside
itself as a background service: node id `embedded`, work folder `<state directory>/work`, asking
the job service directly rather than over HTTP, its outputs published as `file://` references —
holder `embedded`, the local path carried, an empty secret — which placement moves rather than
fetches. When the flag is false the service SHALL stay up and do nothing, so the group it runs in
is not ended; when the encode tools cannot be started it SHALL log the lack and idle rather than
stop the silo.

#### Scenario: one machine is the whole pipeline
- **WHEN** the silo runs with the embedded node on and a job becomes pending
- **THEN** the embedded loop claims it, encodes it, and completes it with an output on the silo's
  own filesystem

Pinned by: `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`). The
flag-off and tool-less arms are pinned by nothing yet.

### Requirement: A claim offers the node's encoders, found once
The worker SHALL learn its capabilities — the encoders its `ffmpeg` reports — the first time it
claims, and SHALL offer that same set with every claim after. Over HTTP the claim SHALL be
`POST /v1/jobs/claim` with the node's id and the capabilities sorted. A claim that answers no job
SHALL mean exactly that: the loop waits and asks again. Which job a claim picks — preferring one
whose source the claimant holds — is the silo's to decide, per [jobs](../jobs/spec.md).

#### Scenario: no work is not an error
- **WHEN** two passes run over a queue that yields one job
- **THEN** the first does the job and the second answers there was none, with the loop still able
  to run a third

Pinned by: `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`, for the
true-then-false shape of a pass). The found-once memoisation is pinned by nothing yet.

### Requirement: The loop polls every few seconds and rides out its errors
The loop SHALL run until it is cancelled: after a pass that found no work, and after any thrown
error, it SHALL sleep the poll interval — five seconds by default, `silo-node --poll` seconds on
the command line — and go on, the error logged rather than raised. A failure inside the one job a
pass holds SHALL be reported to the silo by `fail` with the reason — `cancelled` when the stop
came from outside or from the silo — and SHALL not keep the loop from the next claim. The fail
report's own failure SHALL be swallowed: the job is the silo's to reclaim when the lease lapses.

#### Scenario: a dead ffmpeg does not kill the node
- **WHEN** an encode throws
- **THEN** the job is failed with the error's description, the error is logged, and the loop
  sleeps the poll interval and claims again

Pinned by: nothing yet.

### Requirement: A source the node holds is opened where it is
When the claimed job's source names this node as its holder and carries its local path, the
worker SHALL open the file at that path; a source whose URL is a `file://` URL SHALL likewise be
used in place. Nothing SHALL move in order to reach itself: only a remote source is copied, into
the work folder as `<job id>.source.<ext>` — `mkv` when the source URL names no extension.

#### Scenario: the machine that ripped it encodes it
- **WHEN** a node claims a job whose source it holds, path included
- **THEN** the encode reads that path directly and no fetch happens

Pinned by: `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`, whose
source is a local file the worker opens in place).

### Requirement: A remote source is fetched by range, resuming by offset
A source on another holder SHALL be fetched to the work folder by range, the source's secret sent
as `x-silo-secret`, resuming from the bytes already on disk — a request for `Range: bytes=<have>-`
whose answer is appended — and accepting only 200 and 206, any other status failing as
`the holder answered <status>`. A 200 in answer to a resume SHALL truncate the file and start
over rather than append. When the reference's `sizeBytes` is known, a file that already has it
SHALL be fetched not at all, and a finished fetch SHALL be checked against it, failing as
`got <final> bytes of <size>`.

#### Scenario: an interrupted fetch resumes
- **WHEN** 1234 bytes of a 5000-byte source sit in the work folder from an earlier attempt
- **THEN** the holder is asked from byte 1234 and the file on disk afterwards is the source,
  byte for byte

Pinned by: `Tests/SiloTests/FileServerTests.swift` (`aPublishedFileIsFetchedByRangeWithItsSecretAndByNothingElse`).

### Requirement: The recipe becomes one encode in the work folder
A claimed job with no recipe or no merged facts SHALL fail at once, with
`job <id> has no recipe to run`. Otherwise the worker SHALL clear any stale output and encode the
source to `<job id>.<the recipe's output extension>` in the work folder, run with the one
argument list the recipe spells for that input and output; ffmpeg's own progress SHALL become the
job's progress, the fraction the seconds done over the source's recorded duration, never above 1.

#### Scenario: the recipe decides the output
- **WHEN** a pending job whose recipe produces an `mkv` is run
- **THEN** the output is `<job id>.mkv` in the work folder, made by the recipe's own arguments

Pinned by: `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`, which
asserts the `<job id>.mkv` name). The not-ready arm is pinned by nothing yet.

### Requirement: Progress doubles as heartbeat, and the answer carries the cancel
While an encode runs the worker SHALL report the latest progress every progress interval — five
seconds by default — each report renewing the job's lease on the silo. The state that comes back
SHALL steer the loop: an answer of `cancelling` or `cancelled` stops the encode and ends the
attempt with a `fail` of `cancelled`. Whichever of the encode and the reporter finishes first
SHALL end the other: a finished encode silences the reporter, a cancellation abandons the
encode.

#### Scenario: the operator cancels mid-encode
- **WHEN** the silo marks the encoding job `cancelling`
- **THEN** the node's next report is answered `cancelling`, the encode is abandoned, and the job
  is failed with `cancelled`

Pinned by: nothing yet (the silo's half of the exchange is pinned by `Tests/SiloTests/JobTests.swift`,
`aJobGoesFromRegisteredToPlaced`).

### Requirement: The output is probed and its layout checked against the recipe
When the encode returns, the worker SHALL probe the output with ffprobe and check the layout the
probe sees against the recipe. The completion's result SHALL record the output's size, its
video, audio and subtitle streams as `<kind> <codec>` in probed order, and whether the layout
matched. Any mismatch SHALL instead fail the job with
`the output's layout is not the recipe's: <mismatches>` — an output whose layout is not the
recipe's is never reported complete.

#### Scenario: the made file is measured against the recipe
- **WHEN** the encode of a one-second sample finishes
- **THEN** the result's streams are `["video h264", "audio flac", "audio aac"]`, the layout
  matched, and the job becomes `encoded`

Pinned by: `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`). The
mismatch-fails-the-job arm is pinned by nothing yet (the silo's half is pinned by
`aMismatchedLayoutFailsAndALapsedLeaseIsReclaimed` in the same file).

### Requirement: Completion names where the output is, and the output stays served until placement
Before reporting completion the worker SHALL publish the output — a node on another machine
serving it at `<job id>/output` on its file server's port, 18600 unless configured, the returned
reference carrying the node's own id as holder — and SHALL then complete the job with that
reference and the result. Publication comes first, so the silo never holds a reference to a file
it cannot reach. The output SHALL stay on the node that made it, served under its secret, until
the silo fetches it at placement; the embedded node's output SHALL instead be a `file://`
reference placement moves on the same filesystem.

#### Scenario: the output waits where it was made
- **WHEN** a remote node completes a job
- **THEN** the completed reference's URL, holder and secret are the node's, and the file is
  served for the silo's fetch at placement

Pinned by: `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`, for the
embedded output moved at placement). The remote serving half is pinned by nothing yet.

### Requirement: The client a node speaks with is Foundation alone
The HTTP `JobsAPI` SHALL be hand-written over Foundation's `URLSession` and nothing else: the
client's only dependency is SiloKit's own types. It SHALL send and read JSON with ISO-8601 dates,
ask `Accept: application/json`, and send `Authorization: Bearer <token>` when it holds a token —
claims, reports, completions and failures carry the node's token, whose issuance and checking are
the nodes capability's. Every answer outside 200–299 SHALL be thrown as
`the silo answered <status>`. On Linux `FoundationNetworking` fills in; no further dependency is
permitted, so the ingestion tool links it as easily as the node does.

#### Scenario: a refusal is an error that names the status
- **WHEN** the silo answers a claim with 401
- **THEN** the client throws `the silo answered 401`, and the loop logs it and polls again

Pinned by: nothing yet.
