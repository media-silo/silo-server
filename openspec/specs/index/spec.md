<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# The index

## Purpose

The index is what every read route answers from: one SQLite file in the silo's state directory,
derived from a library's sidecars, holding nothing they do not, and rebuilt from them when it is
thrown away. How the silo keeps its rulesets, the other thing in its state directory that routes
read, is [rulesets](../rulesets/spec.md).

Rationale: [Silo proposal — The index](../../../Proposals/Silo.md) — derived state, a cache
that can be thrown away; principle 1 (the `.smd` is the truth).
Documentation: [README](../../../README.md).

## Requirements

### Requirement: The index is derived state, kept as one SQLite file
The index SHALL be one SQLite file, `index.sqlite` in the state directory the silo was
configured with, opened with a five-second wait on a lock rather than a failure, so the
operator's command line and the silo may open the one file. Its schema SHALL be one table
per sidecar element the read path answers — container, item, presentation and external
reference — plus a table recording each sidecar's library, path, modification time and
size. The container row SHALL keep the sidecar's bytes, so one container's detail, or its
`.smd` projection, is one read and one parse rather than a join across tables. Deleting the
file SHALL lose nothing the sidecars do not say: an index opened at the same path starts
empty and a scan fills it again.

#### Scenario: the file can be thrown away
- **WHEN** a library is scanned into an index at a file, the file is deleted, and a fresh
  index is opened at the same path
- **THEN** the fresh index holds no containers and no presentations, and a scan of the
  library reads the sidecar again

#### Scenario: an index survives being reopened
- **WHEN** an index is opened at a file a previous index already scanned a library into
- **THEN** it answers from what the file holds — one container and one presentation for the
  fixture library

Pinned by: `Tests/SiloStoreTests/IndexTests.swift` (`theIndexIsAFileThatCanBeThrownAway`).

### Requirement: Boot and scans re-parse only the sidecars that changed
A scan SHALL walk a library from its top-level folders — skipping hidden files and any
folder without a `container.smd` — descending into the children each sidecar declares. A
sidecar whose recorded modification time and size are unchanged SHALL NOT be read again;
its children are taken from the index instead, and a parent that moved is corrected. One
sidecar's read SHALL replace everything the index holds for its container — row, items,
presentations, external references and sidecar record — in one write. Containers whose
sidecars the walk no longer reaches SHALL be removed. A sidecar on disk that nothing
references SHALL be reported as a warning; an unreadable sidecar, a child whose id is not
what its parent expects, and a child path that escapes its container's folder or does not
exist SHALL be reported as errors and not indexed. The scan SHALL report what it did as
counts of `read`, `unchanged` and `removed` together with the findings. The server SHALL
scan every configured library at boot, before the first request is answered; the same
incremental walk SHALL run on demand as `Indexer.scan`, and `Indexer.refresh` SHALL
re-read one container's sidecar alone, for a container already reachable.

#### Scenario: a first scan reads everything
- **WHEN** a library of four placed containers is scanned
- **THEN** the report reads 4 and leaves 0 unchanged, and the index holds the containers in
  order, the unlisted series out of the listed roots, the serial's parent and folder as
  `0000000000000002` and `Doctor Who (1963)/Season 13/Pyramids of Mars`, and each
  presentation's id as the stable hash of its library and path

#### Scenario: a second scan reads nothing
- **WHEN** the same library is scanned again unchanged
- **THEN** the report reads 0 and leaves 3 unchanged

#### Scenario: a placement's sidecar is the only one read
- **WHEN** one placement changes one of three sidecars and a scan runs
- **THEN** the report reads 1 and leaves 2 unchanged

#### Scenario: one container is refreshed
- **WHEN** `Indexer.refresh` is called on `Doctor Who (1963)/Season 13/Pyramids of Mars`
  after a placement wrote its sidecar
- **THEN** the report reads 1 and the index holds the container's three presentations

#### Scenario: a sidecar that disappears
- **WHEN** the `Season 13` sidecar is deleted and a scan runs
- **THEN** the report's `removed` is 2 and its findings are the error
  `child 0000000000000002 is at "Season 13/container.smd", which does not exist` on the
  series and the warning `a sidecar nothing references` on the now-orphaned serial, and the
  index forgets both containers

Pinned by: `Tests/SiloStoreTests/IndexTests.swift` (`aScanIndexesWhatThePlacerWrote`,
`aSecondScanReadsOnlyWhatChanged`).

### Requirement: A placement the server applies brings the index up to date itself
After the server applies a placement it SHALL bring the index up to date itself, by an
incremental scan of the library, so the placed presentation is indexed and served without
a scan being requested. An unchanged sidecar costs a stat, so the whole library is
re-walked rather than only the container the placement rewrote; `Indexer.refresh` remains
the one-container entry point.

#### Scenario: a placed presentation is served without a requested scan
- **WHEN** `POST /v1/libraries/main/place` applies a placement for item `part2`
- **THEN** `GET /v1/media/{presentation}` for the answer's presentation id answers 206, and
  `GET /v1/containers/0000000000000003` shows the placed `Part Two.mkv` at once

Pinned by: `Tests/SiloTests/ServerTests.swift` (`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).
