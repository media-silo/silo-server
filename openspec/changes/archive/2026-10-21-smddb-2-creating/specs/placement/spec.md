<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A tree of containers is made in a library as a placement would make it, with no file
SiloLibrary SHALL compute, from a library folder, a tree of containers and the folder of the
container that is to hold its top — or the library folder itself, for a tree at the top — every
write that making the tree would make, without making any: the folders to create, parents first;
the sidecar writes; and the findings. Each container's folder SHALL be named as a placement names
it. Each new sidecar SHALL hold its container's own fields, its children's paths among the tree,
and no presentations. An existing sidecar for the holding container SHALL be updated as a placement
updates one, changing only the top's child path, and written only when that is news. The sidecar
writes SHALL list the new sidecars from the top down, and the holding container's last. The writes
SHALL be describable in a placement's words, `create` a folder and `write` or `update` a sidecar.
A folder whose sidecar names another container SHALL be an error-severity finding
(`the folder for <title> already holds <id>`), as in a placement, and so SHALL each validator
error on a new sidecar. Applying SHALL refuse a computation with an error before touching
anything, and otherwise SHALL create the folders, then write the sidecars in the order listed,
atomically. The order keeps the failure mode a placement's: an interrupted apply leaves a sidecar
nothing references, which the walk warns of, rather than a reference to a sidecar that is not
there.

#### Scenario: a series, a season and a serial made in an empty library
- **WHEN** a series holding a season, which holds a serial, is computed into an empty library
- **THEN** the declared writes are three `create`s, the series' folder first, and three `write`s,
  the series' sidecar first, and no file is placed

#### Scenario: a season made beneath a series already there
- **WHEN** a season is computed beneath the folder of a series whose sidecar holds presentations
- **THEN** the declared writes create the season's folder, write its sidecar, and update the
  series' sidecar last, and applying it leaves the series' presentations and own fields as they
  were

#### Scenario: a folder that holds another container
- **WHEN** a container is computed whose folder already holds a sidecar for another container
- **THEN** the computation carries the error `the folder for <title> already holds <id>`, and
  applying it throws and makes nothing

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`aTreeOfContainersIsMadeWithNoFile`).
