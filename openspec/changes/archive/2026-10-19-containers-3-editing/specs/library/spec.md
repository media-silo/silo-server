<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A folder not named as the layout would name it is a warning
The walk SHALL warn of a container's folder whose name is not the one the layout would give the
container from its sidecar now — its display title, sanitised — as
`folder "<name>" is not the name the layout would give it, "<expected>"`, on the container's
sidecar. A folder is named when it is made, and nothing the walk or an edit does SHALL rename
it.

#### Scenario: a year corrected after the folder was made
- **WHEN** a film's folder is `Alien (1997)` and its sidecar's year is 1979
- **THEN** the walk warns on `Alien (1997)/container.smd` that the folder is not the name the
  layout would give it, `Alien (1979)`, and the folder is where it was

Pinned by: `Tests/SiloStoreTests/IndexTests.swift` (`aFolderNotNamedAsTheLayoutWouldNameItIsAWarning`).
