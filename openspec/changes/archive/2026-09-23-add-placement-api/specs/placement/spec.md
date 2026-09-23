<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The server places a finished file into a library on request
The silo SHALL answer `POST /v1/libraries/{library}/place` (operation `placeFile`) from the
operator controller, behind the operator's bearer token: a request without an
`Authorization: Bearer` header matching the configured operator token SHALL be refused 401, and
a library the silo does not serve SHALL be refused 404. The request body SHALL be a JSON
`PlaceRequest`: `containers` — the container the item is in and every container above it, root
first, each as its repository XML document — `item`, and the `file` as a path the silo can
reach, all required; `alternative`, `profile`, `tracks`, `chapters`, `source`, `copy` and
`dryRun` optional. A container document that cannot be read, a lineage that does not hold
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

### Requirement: A placement is shown before it is applied
The answer SHALL be a `PlacementResult`: `applied`, the `destination` as the file's path in the
library relative to its root, the `presentation` id absent until the placement is applied, the
`writes` — the declared write targets, one per line — and the `findings`. A request whose
`dryRun` is true SHALL be answered 200 with that body, `applied` false, `presentation` absent,
and SHALL move and copy nothing; the file stays where it was.

#### Scenario: a dry run shows the writes and moves nothing
- **WHEN** `POST /v1/libraries/main/place` names item `part2` of Pyramids of Mars with a track
  mapping `commentary1` to audio 2, a chapter titled `Opening`, and `dryRun: true`
- **THEN** the answer is 200 with `applied` false and no `presentation`, `destination` is
  `Doctor Who (1963)/Pyramids of Mars/Part Two.mkv`, the last of the `writes` is
  `update   Doctor Who (1963)/Pyramids of Mars/container.smd`, and the named file still exists
  where it was

Pinned by: `Tests/SiloTests/ServerTests.swift` (`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).

### Requirement: Applying a placement moves the file and tells the index
Unless `dryRun`, an applicable placement SHALL be applied and answered 200 with `applied` true
and `presentation` set to the placed presentation's id — what the media route takes. The file
is moved into place: it no longer exists where it was. After applying, the server SHALL
re-read the library into its index itself, by an incremental scan, so the placed presentation
is indexed and served without a scan being requested.

#### Scenario: an applied placement moves the file into place
- **WHEN** the same body is sent with `dryRun: false`
- **THEN** the answer is 200 with `applied` true and a `presentation` id, and the file no
  longer exists at its original path

#### Scenario: the placed presentation is served without a requested scan
- **WHEN** `GET /v1/media/{presentation}` is asked for `bytes=0-9` of the answer's id
- **THEN** the answer is 206, and `GET /v1/containers/0000000000000003` shows the file
  `Part Two.mkv` and its chapter titled `Opening`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).

### Requirement: The file is copied instead of moved when asked
A request whose `copy` is true SHALL apply the placement by copying the file into place, leaving
the original where it was, rather than moving it.

#### Scenario: a copy leaves the source in place
- **WHEN** an applicable request carries `copy: true`
- **THEN** the placement is applied with the file at its destination and still at its original
  path

Pinned by: nothing yet.

### Requirement: A refused placement is answered whole, with its findings
A placement an error-severity finding stops SHALL NOT be applied: no file moves, no sidecar
changes. The answer SHALL be 409 carrying the `PlacementResult` — `applied` false and the
findings shown — so the caller reads what refused it.

#### Scenario: a destination that already exists
- **WHEN** the same body is placed a second time, the first placement having succeeded
- **THEN** the answer is 409 with `applied` false, the findings include
  `already exists; nothing is overwritten`, and the file offered for placing remains where it
  was

Pinned by: `Tests/SiloTests/ServerTests.swift` (`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).
