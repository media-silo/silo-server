<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The index is derived state, kept as one SQLite file
The index SHALL be one SQLite file, `index.sqlite` in the state directory the silo was
configured with, opened with a five-second wait on a lock rather than a failure, so the
operator's command line and the silo may open the one file. Its schema SHALL be one table
per sidecar element the read path answers — container, item, presentation and external
reference — plus a table recording each sidecar's library, path, modification time and
size. The container row SHALL keep the sidecar's bytes, so one container's detail, or its
`.smd` projection, is one read and one parse rather than a join across tables. A container's
rows SHALL be keyed by its library and its id, since one container may be filed in several
libraries, each with a sidecar of its own: a library's walk SHALL write and remove only that
library's rows, and a container in two libraries SHALL be held twice, each as its own library's
sidecar says. Deleting the file SHALL lose nothing the sidecars do not say: an index opened at
the same path starts empty and a scan fills it again.

#### Scenario: the file can be thrown away
- **WHEN** a library is scanned into an index at a file, the file is deleted, and a fresh
  index is opened at the same path
- **THEN** the fresh index holds no containers and no presentations, and a scan of the
  library reads the sidecar again

#### Scenario: an index survives being reopened
- **WHEN** an index is opened at a file a previous index already scanned a library into
- **THEN** it answers from what the file holds — one container and one presentation for the
  fixture library

#### Scenario: one container in two libraries
- **WHEN** two libraries each hold a sidecar for one container, each with a presentation of
  its own, and the first library's sidecar is then deleted and both libraries are scanned
- **THEN** before the deletion the index holds the container once for each library, each with
  its own library's presentation, and after it holds the container for the second library
  alone, with that library's presentation

Pinned by: `Tests/SiloStoreTests/IndexTests.swift` (`theIndexIsAFileThatCanBeThrownAway`).
Keying a container by its library is pinned by nothing yet.
