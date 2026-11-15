<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The silo remembers what it deleted
The silo SHALL record each library it removes, each recipe it discards and each trial it deletes, by
its kind, its id and when, in `deleted.json` in its state directory, written whole and atomically once
the delete has been made, and SHALL keep each entry for thirty days. A delete whose entry could not be
written SHALL still be answered as made. A library's entry SHALL be taken off the record when a library
is added under its id again. Each route that deletes SHALL answer a delete of an id the record holds for
its kind as it answered the delete, 204, and changing nothing; an id the record does not hold SHALL be
answered as the route answers an id the silo never had.

#### Scenario: a delete sent again
- **WHEN** the operator discards a resolved recipe, and sends the same delete again
- **THEN** both answers are 204

#### Scenario: an id never held
- **WHEN** the operator discards a recipe id the silo has never held
- **THEN** the answer is 404

#### Scenario: a delete long ago
- **WHEN** a recipe was discarded thirty-one days ago, and the delete is sent again
- **THEN** the answer is 404

#### Scenario: the record across a restart
- **WHEN** a trial is deleted, the silo stops and starts again, and the delete is sent again
- **THEN** the answer is 204

Pinned by: nothing yet.

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
mount or automount unit in `/etc/systemd/system` or `/run/systemd/system` or enabled from there. The id SHALL be new,
unless the library the silo serves under it is at the same path, once standardised: that SHALL be
answered 200 with the library as it stands, adding and walking nothing, so that an add sent again is
answered with the library the first added. An id taken at another path SHALL be 409; a path outside every root, any path when the roots are empty, or folders
that would be made outside a root or where a drive mounts SHALL be 403, whether or not `create` was given,
since asking would not make them; otherwise a path that does not exist without `create`, or that
passes through something that is not a folder, SHALL be 422. An added library SHALL be written to
`settings.json`, walked before the route answers, and served without a restart. The silo SHALL
serve `DELETE /v1/libraries/{library}` behind the same gate; it SHALL be 409 while a job not yet in a
final state names the library, and otherwise SHALL remove the library from `settings.json` and its
rows from the index, touching nothing on disk, and answer 204. A library the silo does not serve SHALL
be 404, unless the silo removed it, as its record of what it deleted holds.

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

#### Scenario: an add sent again
- **WHEN** the operator adds `films` at `/srv/media/films`, sends the same request again, and then adds
  `films` at `/srv/media/other`
- **THEN** the answers are 201, 200 with the same library, and 409

#### Scenario: a removal sent again
- **WHEN** the operator removes a library no live job names, and sends the same removal again
- **THEN** both answers are 204, and an id the silo never served is 404

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
`mountPointsAreReadAsTheMachineHasThem`, `mountPointsAreReadFromSystemdUnits`). An add and a
removal sent again are pinned by nothing yet.
