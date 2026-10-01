<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

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
walk every available library at boot, before the first request is answered; after a placement
it applies; when a library is added; when an unavailable library's folder returns; and every
five minutes regardless. Walks of one library SHALL NOT overlap: a walk asked for while one runs
SHALL join it and share its report, and different libraries SHALL walk independently. A walk that
finds no container at a library's top level while the index holds containers for it SHALL NOT be
applied, and the library SHALL be unavailable instead, per [read-api](../read-api/spec.md). The
same incremental walk SHALL run on demand as `Indexer.scan`, and `Indexer.refresh` SHALL re-read
one container's sidecar alone, for a container already reachable; the media route SHALL call it
for a presentation whose file it finds missing, before answering.

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

#### Scenario: a change behind the server's back
- **WHEN** a sidecar is changed on disk by something other than the server
- **THEN** the next five-minute walk reads it, with nobody asking

#### Scenario: an empty mount point forgets nothing
- **WHEN** a library's folder exists but is empty, and the index holds containers for it
- **THEN** the walk is not applied, the containers remain in the index, and the library is
  unavailable

#### Scenario: walks join
- **WHEN** a placement's walk is asked for while the tick's walk of the same library is running
- **THEN** the library is walked once, and both share its report

Pinned by: `Tests/SiloStoreTests/IndexTests.swift` (`aScanIndexesWhatThePlacerWrote`,
`aSecondScanReadsOnlyWhatChanged`). The triggers, joining and the empty-walk rule are pinned by
nothing yet.
