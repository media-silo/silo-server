<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## RENAMED Requirements

- FROM: `### Requirement: Placement fetches the output from its holder and files it`
- TO: `### Requirement: Placement is taken at once, and fetches the output from its holder and files it`

## MODIFIED Requirements

### Requirement: Placement is taken at once, and fetches the output from its holder and files it
`POST /v1/jobs/{id}/place` SHALL take an `encoded` job with its output present: it SHALL set the job
`placing`, queue it to be placed, and answer 202 with the job before any of the placement is made. A
`placing` job SHALL be answered 202 as it stands and queued no second time, so that a place sent while
the placement is made is answered with the work under way. A `placed` job SHALL be answered 200 as it
stands, its placement summary included, so that a place sent again is answered as the first was;
anything else is 409; and a binding naming a library the silo no longer has is 404. The job SHALL stay
`placing` while the silo works, and the client SHALL learn how the placement ended from the job,
`GET /v1/jobs/{id}`. Queued jobs SHALL be placed side by side, each library's writes in its lane. On
start the silo SHALL queue every job left `placing`, so no job stays `placing` with nothing placing it;
a staged copy left whole by the stop SHALL be the one placed, since an output moved from the embedded
node's work folder is no longer there. The output SHALL be staged at `<library>/.silo/incoming/<job id>.<ext>`: moved
across when the output is a file URL — the embedded node's output is on this filesystem already —
and fetched over HTTP with the file's secret in `x-silo-secret` when it is remote, a non-200 answer
failing the placement (`the node answered <status> for the output`). The presentation SHALL be built from the
binding of the job's recipe — its item, alternative and chapter names, its feature map renumbered by
the recipe's layout — in the profile of the recipe's output, with its provenance: a `<source>` naming
the binding and holding one `<segment>` per segment in order, each its source's natural key when it
has one and its chapter span when it has one, and a `<transform>` holding the recipe's stack, its
ruleset and version and a `<layer>` for each layer above it with its version and digest; the placement
computed and, when it would not apply, refused whole with its reasons as the failure; otherwise applied, and
each sidecar it wrote re-read into the index, as [index](../index/spec.md) sets out, so the index
learns of the new presentation without the library being walked. The job SHALL then be `placed`
with a summary of the destination relative to the library root, the presentation's id, and the
writes made. Any failure along the way SHALL return the job to `encoded` with the failure recorded.

#### Scenario: an encoded job is placed
- **WHEN** the operator places an encoded job whose binding is part three of the serial *Pyramids of
  Mars*, in the series *Doctor Who (1963)* in library `main`, made by the unqualified output
- **THEN** the place is answered 202 with the job `placing`, and the job is then `placed` at `Doctor Who (1963)/01 - Pyramids of Mars/Part Three.mkv`, the index
  answers its presentation id (and the media route serves it by range), the serial's sidecar names
  the binding and the recipe's ruleset version on the presentation, and a second place is answered 200
  with the job, `placed`, writing nothing

#### Scenario: a place sent while the job is placed
- **WHEN** a place is sent again while the job it named is `placing`
- **THEN** the answer is 202 with the job, `placing`, and the job is placed once

#### Scenario: a placement refused
- **WHEN** a job is placed whose placement would not apply
- **THEN** the place is answered 202, and the job is then `encoded` with the placement's reasons as its
  failure

#### Scenario: a job left placing by a stop
- **WHEN** the silo starts with a job `placing`
- **THEN** the job is placed without anyone asking, from its staged copy when that is whole

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromResolvedToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`). A placement taken at once, sent again while `placing`, refused, or taken up at a start, is pinned by nothing yet.

### Requirement: The operator drives the queue with `silo-ctl jobs`
`silo-ctl jobs` SHALL offer `list` (oldest first, with `--state` to filter), `show` (one job,
whole, as JSON), `cancel`, `retry` and `place`, each naming the job by id. The silo SHALL be
reached by `--silo` or `SILO_URL` and the operator's token given by `--token` or `SILO_TOKEN`,
through the Foundation-only client. Each changing command SHALL print the job as one line: its
id, its state padded to ten, the percent done when encoding, `-> item (profile)` naming its
recipe's binding's item and its output's profile, `at destination` when placed, and `! failure`
when failed. `place` SHALL read the job every second while it is `placing`, and then print it, and each
of the placement's writes once it is `placed`. A job keeps its recipe by
id, so the command SHALL fetch each recipe and each binding it names, a binding once.

#### Scenario: watching the queue
- **WHEN** the operator runs `SILO_URL=http://localhost:8742 SILO_TOKEN=secret silo-ctl jobs list`
- **THEN** the queue is printed oldest first, one line a job, or `no jobs`

Pinned by: nothing yet.
