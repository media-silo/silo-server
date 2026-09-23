<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

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
- **THEN** the declared writes are `create   Doctor Who (1963)/`, `create   Doctor Who (1963)/Season 13/`, `create   Doctor Who (1963)/Season 13/Pyramids of Mars/`, `place    <source> -> Doctor Who (1963)/Season 13/Pyramids of Mars/Part One.mkv`, `write    Doctor Who (1963)/container.smd`, `write    Doctor Who (1963)/Season 13/container.smd` and `write    Doctor Who (1963)/Season 13/Pyramids of Mars/container.smd`, and the recorded presentation's `file=` is `Part One.mkv`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`theFirstPlacementMakesTheTree`).

### Requirement: A placement needs a lineage that holds together
`Placer.compute` SHALL throw — producing no placement — when the lineage is empty
(`a placement needs at least the container the item is in`), when a container in the lineage does
not hold the next (`<parent> does not hold <child>`), or when the item is not one of the target
container's sequence items or extras (`<container> has no item <id>`). These are errors told to the
caller, not findings a client would read.

#### Scenario: broken requests are thrown
- **WHEN** the lineage is empty, or is `[Doctor Who (1963), Pyramids of Mars]` with Season 13 skipped, or names item `part9`
- **THEN** each compute throws its `PlacementError` and no writes are described

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`whatCannotBePlacedIsRefusedWithReasons`).

### Requirement: Folders and sidecars are made only as news
A placement SHALL create each lineage folder that has no sidecar yet, and SHALL leave the rest. An
ancestor's sidecar SHALL record the child's `<folder>/container.smd` path and SHALL be written only
when that is news — an ancestor that already knows its child is not rewritten. A placement of an
extra SHALL add the container's `extras/` folder when it is not there.

#### Scenario: the first placement makes the tree
- **WHEN** the library is empty
- **THEN** the placement creates all three lineage folders and writes all three sidecars, root first

#### Scenario: a second placement updates only what changed
- **WHEN** part1 is placed again as `Part One - mobile.mkv` with the tree already there
- **THEN** the placement creates no folders, writes only `Doctor Who (1963)/Season 13/Pyramids of Mars/container.smd`, and placing the extra creates exactly one folder: `extras`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`theFirstPlacementMakesTheTree`,
`aSecondPlacementUpdatesOnlyWhatChanged`).

### Requirement: Existing sidecars are updated, not regenerated
When a lineage folder's `container.smd` already exists, the placement SHALL read it and write back
an update of that document rather than a regenerated one: comments stay, order stays, anything
hand-written stays, and only the presentations and the children's `smd` paths change — a sidecar a
person edited by hand keeps its comments and its order through a placement, and the container's own
fields are never rewritten, the lineage's value being the authority. An update SHALL merge the
on-disk children and presentations into the container the lineage carries. A folder whose existing
sidecar names a different container SHALL be an error-severity finding
(`the folder for <title> already holds <id>`), never an overwrite, and a sidecar that cannot be
read SHALL be an error-severity finding (`unreadable: …`).

#### Scenario: a hand edit survives a placement
- **WHEN** `<!-- mine -->` is inserted by hand before the serial's `<title>` and two more presentations are then placed
- **THEN** the serial's sidecar still contains `<!-- mine -->` and its presentations list reads `Part One.mkv`, `Part One - mobile.mkv`, `Part One - Updated special effects.mkv`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`aSecondPlacementUpdatesOnlyWhatChanged`).
The already-holds and unreadable findings are pinned by nothing yet.

### Requirement: Findings collect, and any error refuses the whole placement
Computation SHALL collect findings rather than stop at the first error: an alternative the target
does not have (`<title> has no alternative <id>`), a feature the target does not have
(`<title> has no feature <id>`), a destination that already exists
(`already exists; nothing is overwritten`), a source that is not there
(`the source <path> is not there`), an ancestor's conflict or unreadable sidecar, and the
validator's error-severity findings on the item's updated sidecar. A placement with any error
SHALL be inapplicable, and applying it SHALL throw `refused` with the findings and make none of
its writes.

#### Scenario: the same presentation twice is refused with reasons
- **WHEN** part1's default presentation is placed and then placed again from `b.mkv`
- **THEN** the errors are `already exists; nothing is overwritten` and `item part1 has two presentations for the same alternative and profile`, applying throws, and `b.mkv` is still where it was

#### Scenario: a wrong reference shows every reason
- **WHEN** part2 is placed with alternative `omnibus`, a track for feature `music1`, and a missing source
- **THEN** the errors are `Pyramids of Mars has no alternative omnibus`, `Pyramids of Mars has no feature music1`, `the source … is not there`, `item part2: presentation names alternative omnibus, which is not there` and `item part2: a track for feature music1, which is not there`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`whatCannotBePlacedIsRefusedWithReasons`).

### Requirement: Applying a placement writes the file before the sidecars
`Placer.apply` SHALL create the folders with their intermediate directories, then move the source
file to the destination — copy it instead when asked — then write the sidecars atomically, root
first and the item's container last. The order keeps the failure mode honest: the sidecar, the
reference, is written last, so an interrupted placement leaves a file nothing references rather
than a reference to a file that is not there — a state a person can recover, not the
error-severity `"<file>" is not there` the validator gives a dangling reference. Applying SHALL
refuse an inapplicable placement before touching anything.

#### Scenario: an apply moves the source
- **WHEN** an applicable placement is applied with the default move
- **THEN** the source path no longer exists and `placement.destination` holds the file

#### Scenario: a refusal moves nothing
- **WHEN** an inapplicable placement is applied
- **THEN** it throws, and the source file is still where it was

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`theFirstPlacementMakesTheTree`,
`whatCannotBePlacedIsRefusedWithReasons`). The copy variant is pinned by nothing yet.

### Requirement: `silo-ctl place` places a file with no server
The command SHALL take the library folder, a clone of the data repository the container tree is
read from, the container by id — refusing anything that is not sixteen lowercase hexadecimal
characters with `<value> is not a container id: sixteen lowercase hex characters` — the item by id,
an optional alternative and profile, repeatable `--track feature=audio:N[,subtitle:M]` and
`--chapter N=title`, an optional `--source disc=playlist`, a `--copy` flag, a `--dry-run` flag, and
the finished file as its argument. It SHALL walk parents up from the named container to build the
lineage, compute the placement, print the declared writes and every finding, exit with failure
when the placement is inapplicable, make no writes on `--dry-run`, and otherwise apply the
placement and print `placed as <file>`. The writes are shown first, so the dry run differs from a
real run only in that nothing moves.

#### Scenario: the dry run shows the writes and makes none
- **WHEN** `silo-ctl place --library ~/Library --repository ~/data --container 0123456789abcdef --item part1 --track commentary1=audio:2 --chapter "1=Opening titles" --dry-run out.mkv` is run
- **THEN** the declared writes and any findings are printed and neither the library nor `out.mkv` changes

Pinned by: nothing yet.
