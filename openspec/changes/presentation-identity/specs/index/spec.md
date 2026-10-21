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
walk every available library at boot, before the first request is answered; when a library is
added; when an unavailable library's folder returns; and every
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
  presentation's id as the hash of its library, container, item, alternative and
  profile

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
- **WHEN** a library's folder returns and its walk is asked for while the tick's walk of the same
  library is running
- **THEN** the library is walked once, and both share its report

Pinned by: `Tests/SiloStoreTests/IndexTests.swift` (`aScanIndexesWhatThePlacerWrote`,
`aSecondScanReadsOnlyWhatChanged`, `anEmptyMountPointForgetsNothing`),
`Tests/SiloTests/LibrariesTests.swift` (`aChangeBehindTheServersBackIsReadAtTheNextTick`,
`walksAskedForTogetherWalkOnce`, `aDriveLateToMountIsUnavailableAndTheRestAreServed`),
`Tests/SiloTests/ServerTests.swift` (`aMissingFileRefreshesItsContainer`). The tick's five minutes,
and different libraries walking independently, are pinned by nothing yet.

## ADDED Requirements

### Requirement: A presentation's id is the hash of what it is
A presentation's id SHALL be the 64-bit FNV-1a hash, written as sixteen lowercase hexadecimal
characters, of its library's id, its container's id, its item's id, its alternative and its profile,
joined by `|`, an absent alternative or profile written as the empty string. Nothing else SHALL
contribute to it: not the presentation's file, display name, tracks, chapters, source or transform.
A walk SHALL NOT index two presentations of one container with one id, nor two that name one file: the
second SHALL be reported as an error on the container's sidecar —
`item <id> has two presentations for the same alternative and profile`, or
`item <id>: "<file>" is named by another presentation` — and SHALL NOT be indexed, and the walk SHALL
go on.

#### Scenario: a folder renamed by hand
- **WHEN** a film's folder is renamed by hand, nothing else is changed, and the library is walked
- **THEN** each of the film's presentations has the id it had before the rename

#### Scenario: one shape twice in a sidecar
- **WHEN** a sidecar edited by hand holds two presentations of item `feature` with no alternative and no profile, naming different files
- **THEN** the walk indexes the first, reports `item feature has two presentations for the same alternative and profile` on the sidecar, and indexes the rest of the library

#### Scenario: one file named twice
- **WHEN** a sidecar edited by hand holds two presentations of item `feature`, one with profile `mobile`, both naming `Alien.mkv`
- **THEN** the walk indexes the first, reports that `Alien.mkv` is named by another presentation, and indexes the rest of the library

Pinned by: `Tests/SiloStoreTests/IndexTests.swift` (`aPresentationIsNamedForWhatItIs`).
