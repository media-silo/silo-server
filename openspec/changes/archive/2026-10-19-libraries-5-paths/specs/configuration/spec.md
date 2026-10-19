<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Libraries are added and removed over the network, within the roots
The silo SHALL serve `POST /v1/libraries` behind the operator gate, taking an id, a path and
optionally `create`. The path SHALL be absolute, SHALL once symbolic links are resolved lie within
one of `silo.json`'s library roots, and SHALL exist as a directory — or, with `create`, SHALL have
its missing folders made before the library is added, so long as the folder they are made in exists
and lies within a root once its links are resolved; a root SHALL never be made, and no folder SHALL
be made where a drive mounts — directly within a folder the platform mounts drives in (`/Volumes` on
macOS; `/media`, each folder within it, each folder within `/run/media`, and `/mnt` on Linux), or
within a mount point declared while nothing is mounted on it — by `/etc/fstab`, or by a systemd
mount or automount unit in `/etc/systemd/system` or `/run/systemd/system` or enabled from there. The id SHALL be new.
A taken id SHALL be 409; a path outside every root, any path when the roots are empty, or folders
that would be made outside a root or where a drive mounts SHALL be 403, whether or not `create` was given,
since asking would not make them; otherwise a path that does not exist without `create`, or that
passes through something that is not a folder, SHALL be 422. An added library SHALL be written to
`settings.json`, walked before the route answers, and served without a restart. The silo SHALL
serve `DELETE /v1/libraries/{library}` behind the same gate; it SHALL be 409 while a job not yet in a
final state names the library, and otherwise SHALL remove the library from `settings.json` and its
rows from the index, touching nothing on disk.

#### Scenario: added and served
- **WHEN** `silo.json`'s library roots are `/srv/media` and the operator adds `films` at
  `/srv/media/films`
- **THEN** the answer is the walked library, and `GET /v1/libraries` lists it without a restart

#### Scenario: a link that leads outside
- **WHEN** `/srv/media/escape` is a symbolic link to `/etc` and the operator adds it
- **THEN** the answer is 403 and nothing is written

#### Scenario: empty roots, no additions
- **WHEN** `silo.json`'s library roots are an empty list and the operator adds any library
- **THEN** the answer is 403

#### Scenario: removal leaves the files
- **WHEN** the operator removes a library no live job names
- **THEN** it leaves `settings.json` and the index, and every sidecar and media file under its path
  remains

#### Scenario: missing folders made on request
- **WHEN** `silo.json`'s library roots are `/srv/media`, `/srv/media` exists and `/srv/media/shows`
  does not, and the operator adds `shows` at `/srv/media/shows/new` with `create`
- **THEN** `/srv/media/shows` and `/srv/media/shows/new` are made, and the answer is the walked
  library, available

#### Scenario: missing folders not made unasked
- **WHEN** the operator adds a library at a path within a root, whose last folder does not exist,
  without `create`
- **THEN** the answer is 422 and nothing is made or written

#### Scenario: a missing root is never made
- **WHEN** `silo.json`'s library roots include `/mnt/disk`, which does not exist, and the operator
  adds a library at `/mnt/disk/films` with `create`
- **THEN** the answer is 403 and nothing is made

#### Scenario: no folder made where a drive mounts
- **WHEN** `/Volumes` is a library root on a Mac, no drive named `Media` is mounted, and the operator
  adds a library at `/Volumes/Media/Films` with `create`
- **THEN** the answer is 403, saying the library would be created where drives are mounted, and
  nothing is made

#### Scenario: where a drive mounts, said over the folders being missing
- **WHEN** `/Volumes` is a library root on a Mac, no drive named `Media` is mounted, and the operator
  adds a library at `/Volumes/Media/Films` without `create`
- **THEN** the answer is 403, saying the library would be created where drives are mounted, rather
  than 422 for a path that does not exist

#### Scenario: no folder made in an empty mount point
- **WHEN** `/etc/fstab` declares `/srv/media` as a mount point, nothing is mounted on it, and the
  operator adds a library at `/srv/media/films` with `create`
- **THEN** the answer is 403, naming `/srv/media` as a mount point with nothing mounted on it, and
  nothing is made

#### Scenario: no folder made in an empty mount point a unit declares
- **WHEN** a systemd mount unit in `/etc/systemd/system` declares `/srv/media` as where it mounts,
  nothing is mounted on it, and the operator adds a library at `/srv/media/films` with `create`
- **THEN** the answer is 403, naming the unit's file, and nothing is made

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aLibraryIsAddedWithinTheRootsAndRemovedLeavingItsFiles`,
`aLibrarysPathIsCheckedAndItsMissingFoldersMade`, `yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`,
for the refusal while a live job names the library), `Tests/SiloTests/LibrariesTests.swift`
(`withTheRootsEmptiedNothingIsAddedOverTheNetwork`, `aRootIsMatchedByWholeComponents`,
`aPathIsCheckedAndItsMissingFoldersMadeWithinARoot`, `noFolderIsMadeWhereADriveMounts`,
`mountPointsAreReadAsTheMachineHasThem`, `mountPointsAreReadFromSystemdUnits`).

## ADDED Requirements

### Requirement: A library's path is checked before it is added
The silo SHALL serve `POST /v1/libraries/check` behind the operator gate, taking the body
`POST /v1/libraries` takes and answering 200 with what that addition would find: the path as it would
be written; each folder along it from the top of the filesystem down, as a folder, missing, or not a
folder, stopping at the first that is not a folder; the library root it lies within; the folders an
addition with `create` would make; and the refusal the addition would meet, as its status and detail,
or none. It SHALL make and write nothing. The path's own faults SHALL be found before the id's, so
that a path can be checked before the library is named.

#### Scenario: a path with folders missing
- **WHEN** `silo.json`'s library roots are `/srv/media`, `/srv/media` exists and `/srv/media/shows`
  does not, and the operator checks `/srv/media/shows/new` without `create`
- **THEN** the answer shows `/srv/media` as a folder and `/srv/media/shows` and `/srv/media/shows/new`
  missing, names `/srv/media` as the root and both missing folders as the ones it would make, and
  says the addition would be refused with 422; nothing is made

#### Scenario: a link that leads outside, checked
- **WHEN** `/srv/media/escape` is a symbolic link to a folder outside every root and the operator
  checks `/srv/media/escape/new` with `create`
- **THEN** the answer says the addition would be refused with 403

#### Scenario: a check without the gate
- **WHEN** a client without the operator credential checks a path
- **THEN** the answer is 401, since what exists on the silo's machine is the operator's to learn

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aLibrarysPathIsCheckedAndItsMissingFoldersMade`),
`Tests/SiloTests/LibrariesTests.swift` (`aPathIsCheckedAndItsMissingFoldersMadeWithinARoot`).
