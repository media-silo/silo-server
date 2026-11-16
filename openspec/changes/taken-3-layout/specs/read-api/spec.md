<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A library is laid out again on request
`POST /v1/libraries/{library}/layout` with a JSON body of `dryRun` false SHALL record the library's
layout under way, queue it, and answer 202 with the record before any folder moves; the layout SHALL
then rename every container
folder in the library whose name is not the one the layout gives its container, from the top of
the library down, recording each new path in the sidecar of the container that holds it, and SHALL
re-read the library into the index under the same lock as the moves, so that a request asked for
while folders move waits for the turn and finds each moved container where it went. `GET /v1/libraries/{library}/layout` SHALL answer the
library's last layout: whether it is under way or made, when it was asked for, and once made the
`moves`, each a folder's path relative to the library `from` and `to`, and the `findings`. A layout
asked for while one is under way SHALL be answered 202 with that one, and SHALL NOT be made twice. The
record SHALL be kept as `layouts/<library>.json` in the state directory, replaced by the library's
next layout and removed with the library; a layout recorded under way when the silo starts SHALL be
made again, which moves only what was not moved. A library with no layout SHALL be 404 at the record's
route. A rename that fails SHALL
leave that folder where it is, SHALL be a warning-severity finding,
`folder "<from>" could not be renamed "<to>": <reason>`, and SHALL NOT stop the rest. A dry run SHALL
answer 200 with a `LayoutResult` — `applied` false, the moves it would make, and its findings — move
nothing, and record nothing. A library the silo does not serve SHALL be 404, and
an unavailable one SHALL be 503. A presentation's id SHALL be the same after the layout as before
it. The route SHALL require the operator's bearer; a missing or wrong bearer SHALL be 401.

#### Scenario: a library whose folders were renamed by hand
- **WHEN** a library holds a series whose season is in `Season 13` and whose serial is in
  `Season 13/Pyramids of Mars`, and the operator lays the library out
- **THEN** the layout is answered 202 under way, and once made its record's moves are `Doctor Who (1963)/Season 13` to `Doctor Who (1963)/01 - Season 13` and
  then the serial's folder within it, the sidecars record the new paths, the walk warns of
  nothing, and each presentation has the id it had

#### Scenario: a layout asked for twice
- **WHEN** the operator lays a library out, and asks again while the layout is under way
- **THEN** both are answered 202 with the one record, and each folder is moved once

#### Scenario: a layout left under way by a stop
- **WHEN** the silo starts with a library's layout recorded under way
- **THEN** the library is laid out again, and the record is made

#### Scenario: a dry run
- **WHEN** the operator asks for the layout of a library with `dryRun` true
- **THEN** the answer is 200 and lists the moves, the library is unchanged, and no layout is recorded

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aLibraryIsLaidOutAgain`),
`Tests/SiloLibraryTests/RelayoutTests.swift` (`aLibraryRenamedByHandIsLaidOutFromTheTopDown`),
`Tests/SiloTests/LibrariesTests.swift` (`aRefreshAskedForWhileFoldersMoveFindsWhereTheyWent`). The layout taken at once and its record are pinned by nothing yet.
