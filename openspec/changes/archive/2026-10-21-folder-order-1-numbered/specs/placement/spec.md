<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A placement is computed before it is applied
From a request — the library folder, the item's container and every container above it as a
lineage, the item by id, the presentation to record, and where the finished file is now —
`Placer.compute` SHALL work out every write the placement would make without making any: the
folders to create, parents first; the destination path; the sidecar writes, root first and the
item's container last; the presentation as it will be recorded; and the findings. The request's
presentation SHALL have its `file=` ignored: the layout decides the name. The `<track>` children
SHALL be recorded as the request gives them — they number the output file's streams, the
renumbering from the source's indices having happened in the recipe that made the file — and the
`<chapter>` children SHALL be carried as given. The declared write targets SHALL be describable one
per line, relative to the library: `create` a folder, `place` the file from its source to the
destination, `write` a new sidecar, `update` an existing one.

#### Scenario: the first placement declares the whole tree
- **WHEN** part1 of Pyramids of Mars is computed into an empty library through the lineage Doctor Who (1963), Season 13, Pyramids of Mars, with `<track feature="commentary1" audio="3"/>` and chapter `1=Opening`
- **THEN** the declared writes are `create   Doctor Who (1963)/`, `create   Doctor Who (1963)/01 - Season 13/`, `create   Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/`, `place    <source> -> Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/Part One.mkv`, `write    Doctor Who (1963)/container.smd`, `write    Doctor Who (1963)/01 - Season 13/container.smd` and `write    Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd`, and the recorded presentation's `file=` is `Part One.mkv`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`theFirstPlacementMakesTheTree`).

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
  `Doctor Who (1963)/01 - Pyramids of Mars/Part Two.mkv`, the last of the `writes` is
  `update   Doctor Who (1963)/01 - Pyramids of Mars/container.smd`, and the named file still exists
  where it was

Pinned by: `Tests/SiloTests/ServerTests.swift` (`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).

### Requirement: Folders and sidecars are made only as news
A placement SHALL take, for each container of its lineage below the top, the folder its parent's
sidecar records for it when the parent's sidecar is there and records one, and SHALL name a folder
only for a container its parent does not record, as the layout names it. It SHALL create each lineage
folder that has no sidecar yet, and SHALL leave the rest. An ancestor's sidecar SHALL record the
child's `<folder>/container.smd` path and SHALL be written only when that is news — an ancestor that
already knows its child is not rewritten. A placement of an extra SHALL add the container's
`extras/` folder when it is not there.

#### Scenario: the first placement makes the tree
- **WHEN** the library is empty
- **THEN** the placement creates all three lineage folders and writes all three sidecars, root first

#### Scenario: a second placement updates only what changed
- **WHEN** part1 is placed again as `Part One - mobile.mkv` with the tree already there
- **THEN** the placement creates no folders, writes only `Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd`, and placing the extra creates exactly one folder: `extras`

#### Scenario: a placement into a folder renamed by hand
- **WHEN** a series' sidecar records its season at `Season 13/container.smd`, and a part of a serial of that season is placed
- **THEN** the placement files into `Doctor Who (1963)/Season 13/`, creates no `01 - Season 13` folder, and the series' sidecar is not rewritten

#### Scenario: a placement after a title was corrected in the library
- **WHEN** a series' sidecar records a serial at `01 - Pyramids of Mars/container.smd`, and a part is placed with a lineage whose serial is titled `The Pyramids of Mars`
- **THEN** the placement files into `01 - Pyramids of Mars/` and creates no folder

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`theFirstPlacementMakesTheTree`,
`aSecondPlacementUpdatesOnlyWhatChanged`, `aPlacementFollowsThePathItsParentRecords`).
