<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: `silo-ctl place` places a file with no server
The command SHALL take the library folder, a clone of the data repository the container tree is
read from, the container by id — refusing anything that is not sixteen lowercase hexadecimal
characters with `<value> is not a container id: sixteen lowercase hex characters` — the item by id,
an optional alternative and profile, repeatable `--track feature=audio:N[,subtitle:M]` and
`--chapter N=title`, a `--copy` flag, a `--dry-run` flag, and
the finished file as its argument. It SHALL walk parents up from the named container to build the
lineage, compute the placement, print the declared writes and every finding, exit with failure
when the placement is inapplicable, make no writes on `--dry-run`, and otherwise apply the
placement and print `placed as <file>`. The writes are shown first, so the dry run differs from a
real run only in that nothing moves. A file placed this way records no provenance: it was made
by no binding and no rules the silo knows.

#### Scenario: the dry run shows the writes and makes none
- **WHEN** `silo-ctl place --library ~/Library --repository ~/data --container 0123456789abcdef --item part1 --track commentary1=audio:2 --chapter "1=Opening titles" --dry-run out.mkv` is run
- **THEN** the declared writes and any findings are printed and neither the library nor `out.mkv` changes

Pinned by: nothing yet.

### Requirement: The server places a finished file into a library on request
The silo SHALL answer `POST /v1/libraries/{library}/place` (operation `placeFile`) from the
operator controller, behind the operator's bearer token: a request without an
`Authorization: Bearer` header matching the configured operator token SHALL be refused 401, and
a library the silo does not serve SHALL be refused 404. The request body SHALL be a JSON
`PlaceRequest`: `containers` — the container the item is in and every container above it, root
first, each as its repository XML document — `item`, and the `file` as a path the silo can
reach, all required; `alternative`, `profile`, `tracks`, `chapters`, `copy` and `dryRun`
optional; a presentation placed this way records no provenance. A container document that cannot be read, a lineage that does not hold
together, or an item the container does not have SHALL be refused 400 with a problem detail,
and no placement SHALL be computed over them.

#### Scenario: an unauthenticated request is refused
- **WHEN** `POST /v1/libraries/main/place` is sent with a valid body and no `Authorization` header
- **THEN** the answer is 401

#### Scenario: an unknown library is refused
- **WHEN** `POST /v1/libraries/other/place` is sent with a valid body and the operator's token
- **THEN** the answer is 404

#### Scenario: an item the container does not have is refused
- **WHEN** the body names item `part9`, which the containers do not declare
- **THEN** the answer is 400 and its problem detail contains `has no item part9`

#### Scenario: a container document that cannot be read is refused
- **WHEN** `containers` is `["<nope/>"]`
- **THEN** the answer is 400

Pinned by: `Tests/SiloTests/ServerTests.swift` (`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).
