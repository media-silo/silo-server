<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A container's own fields are edited in one library, on the sidecar the editor read
`PUT /v1/libraries/{library}/containers/{id}` with a JSON `ContainerEdit` — `document`, the
container as its repository XML; `basedOn`, the digest of the sidecar it was made from; and
`dryRun` — SHALL set the container's own fields in that library's sidecar to the document's,
and SHALL change none of the library's facts but the paths of the folders it moves: its
presentations and its rules stay as they stand. A sidecar's digest is the SHA-256 of its bytes as the index read
them, in lowercase hexadecimal, and the `LibraryContainer` a library's container route answers
SHALL carry it as `digest`. The answer SHALL be a `ContainerEditResult`: `applied`, the
sidecar's bytes as written or as they would be, their `digest`, the `findings`, and `moves`, each a
folder's path relative to the library `from` and `to`, made or as they would be made.

- A document that cannot be read, or that names another container, SHALL be 400, and a library
  the silo does not serve or a container it does not hold SHALL be 404.
- A `basedOn` that is not the digest of the sidecar the library holds SHALL be 409, decided
  under the lock the write is made under, with a `Problem` naming the digest it holds; nothing
  SHALL be written.
- An edit whose resulting sidecar has an error-severity finding SHALL be 422, carrying the
  result with its findings, and nothing SHALL be written. Besides the validator's checks, an
  item the document no longer declares SHALL be an error when the library holds presentations
  of it (`item <id> has presentations in this library`) or a sidecar for the container it names
  (`item <id> is a container this library holds`).
- An edit with `dryRun` true SHALL be answered 200 with `applied` false and write nothing.
- Otherwise the silo SHALL write the sidecar; SHALL rename the container's folder when the name
  the layout gives it is no longer the folder's, recording the new path in its parent's sidecar;
  SHALL rename the folder of each child the container holds whose position among its children the
  edit changed, recording each new path in the container's sidecar; SHALL re-read each sidecar it
  wrote, and each container it moved with the containers beneath it, into the index; and SHALL
  answer 200 with `applied` true, so that the next read of the container shows the edit. A rename
  that fails SHALL leave that folder where it is and SHALL be a warning-severity finding,
  `folder "<from>" could not be renamed "<to>": <reason>`; the rest of the edit stands.
- A presentation's id SHALL be the same after a move as before it.

The route SHALL require the operator's bearer, as every route that writes does; a missing or
wrong bearer SHALL be 401.

#### Scenario: a title corrected
- **WHEN** the operator puts a container's document with its year changed from 1997 to 1979,
  based on the digest the library's container route answered
- **THEN** the answer is 200 with `applied` true, the library's container reads the year 1979,
  its folder is renamed from `Alien (1997)` to `Alien (1979)` and listed in `moves`, and its
  presentations, keeping their ids, its children's paths and its rules are as they were

#### Scenario: an edit made from a sidecar that has changed
- **WHEN** an edit is based on a digest, and the sidecar has since been changed by another edit
- **THEN** the answer is 409 naming the digest the library holds, and the sidecar is unchanged

#### Scenario: an alternative a presentation names
- **WHEN** an edit removes the `theatrical` alternative, and the library holds two presentations
  of that alternative
- **THEN** the answer is 422 with an error for each presentation naming the alternative, and the
  sidecar is unchanged

#### Scenario: an item that has presentations
- **WHEN** an edit removes item `part1`, of which the library holds a presentation
- **THEN** the answer is 422 with the finding `item part1 has presentations in this library`,
  and the sidecar is unchanged

#### Scenario: a dry run
- **WHEN** an edit that would apply is put with `dryRun` true
- **THEN** the answer is 200 with `applied` false and the sidecar as it would be written, and the
  sidecar on disk is unchanged

#### Scenario: an edit without the operator's bearer
- **WHEN** an edit is put with no `Authorization` header
- **THEN** the answer is 401

#### Scenario: a season inserted before another
- **WHEN** a series holding Season 13 in `01 - Season 13` is edited to name Season 12 before it
- **THEN** Season 13's folder is renamed `02 - Season 13`, the series' sidecar records
  `02 - Season 13/container.smd`, and the presentations beneath keep their ids

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aContainersOwnFieldsAreEditedOntoTheSidecarRead`,
`anEditMovesTheFoldersItRenames`).

## ADDED Requirements

### Requirement: A library is laid out again on request
`POST /v1/libraries/{library}/layout` with a JSON body of `dryRun` SHALL rename every container
folder in the library whose name is not the one the layout gives its container, from the top of
the library down, recording each new path in the sidecar of the container that holds it, and SHALL
re-read the library into the index. It SHALL answer a `LayoutResult`: `applied`, the `moves`, each a
folder's path relative to the library `from` and `to`, and the `findings`. A rename that fails SHALL
leave that folder where it is, SHALL be a warning-severity finding,
`folder "<from>" could not be renamed "<to>": <reason>`, and SHALL NOT stop the rest. A dry run SHALL
answer the moves it would make and move nothing. A library the silo does not serve SHALL be 404, and
an unavailable one SHALL be 503. A presentation's id SHALL be the same after the layout as before
it. The route SHALL require the operator's bearer; a missing or wrong bearer SHALL be 401.

#### Scenario: a library whose folders were renamed by hand
- **WHEN** a library holds a series whose season is in `Season 13` and whose serial is in
  `Season 13/Pyramids of Mars`, and the operator lays the library out
- **THEN** the moves are `Doctor Who (1963)/Season 13` to `Doctor Who (1963)/01 - Season 13` and
  then the serial's folder within it, the sidecars record the new paths, the walk warns of
  nothing, and each presentation has the id it had

#### Scenario: a dry run
- **WHEN** the operator asks for the layout of a library with `dryRun` true
- **THEN** the answer lists the moves and the library is unchanged

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aLibraryIsLaidOutAgain`).
