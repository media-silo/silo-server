<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

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

### Requirement: Rulesets are kept as the documents they were given
The rulesets store SHALL keep each ruleset under `rulesets/<name>/<version>.xml` in the
state directory — the name the folder, the version the file's name — and SHALL keep the
bytes exactly as they were given, so that a hand-written comment survives. A read SHALL
return the document at a version, or the latest version when none is asked, and a ruleset
parsed from the store SHALL be named and numbered by where it was found, not by what its
document says.

#### Scenario: a stored version reads back byte for byte
- **WHEN** the household ruleset is stored twice and version 1 is then read back
- **THEN** the document returned for version 1 equals, byte for byte, the document that was
  stored

Pinned by: `Tests/SiloTests/ServerTests.swift` (`rulesetsAreVersionedAndTheOperatorGateHolds`).

### Requirement: Every store is a new version the silo numbers, and a version is never rewritten
A store SHALL be assigned the next version for its name — the latest plus one, or 1 for a
new name — read and taken under one lock, so no two stores receive the same number. A
version SHALL NOT be rewritten: a file already on disk under that version is refused as
`versionExists`. A document SHALL be parsed before it is stored, and a document the reader
refuses SHALL NOT be stored at all. A name that is empty, contains a `/`, or begins with a
`.` SHALL be refused as `invalidName`.

#### Scenario: two stores are numbered in order
- **WHEN** the same document is stored as `household` twice
- **THEN** the first store is version 1, the second version 2, and the latest version of
  `household` is 2

#### Scenario: a document that is not a ruleset is refused
- **WHEN** a document testing a fact a rule cannot test — `<when fact="nope" is="1"/>` — is
  stored
- **THEN** it is not stored; over the API the answer is 400 with
  `not a fact a rule can test` in the problem detail

Pinned by: `Tests/SiloTests/ServerTests.swift` (`rulesetsAreVersionedAndTheOperatorGateHolds`).
The `invalidName` and `versionExists` guards are pinned by nothing yet.
