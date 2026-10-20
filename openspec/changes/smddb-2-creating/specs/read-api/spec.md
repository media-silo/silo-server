<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: Containers are made in a library without a file
`POST /v1/libraries/{library}/containers` with a JSON `ContainerCreate` — `documents`, one or more
containers as repository XML; `parent`, the id of a container the library holds, or absent; and
`dryRun` — SHALL make each container in that library as a placement would make it, and SHALL place
no file. The documents SHALL form one tree: exactly one of them, the top, is named as a child by
none of the others, and every other is named as a child by a document in the request. With a
`parent`, the top SHALL be filed beneath the parent's folder; without one, at the top of the
library. Each container's sidecar SHALL hold the document's own fields and no presentations, and
each parent's sidecar SHALL record its child's path. The answer SHALL be a `ContainerCreateResult`:
`applied`, the `writes`, each a sidecar's path relative to the library and whether it is new, and
the `findings`.

- A document that cannot be read, or documents that do not form one tree, SHALL be 400, and a
  library the silo does not serve or a `parent` it does not hold SHALL be 404.
- A request with an error-severity finding SHALL be 422, carrying the result with its findings, and
  nothing SHALL be written. Besides the validator's checks on each sidecar, it SHALL be an error
  when the library already holds a container in the request
  (`container <id> is already at "<path>"`), when the parent's own fields do not name the top as a
  child (`<parent> does not name <top> as a child`), and when a folder the request would use holds a
  sidecar for another container (`the folder for <title> already holds <id>`).
- A request with `dryRun` true SHALL be answered 200 with `applied` false and write nothing.
- Otherwise the silo SHALL make the folders, write the new sidecars from the top down and then the
  parent's, re-read each sidecar it wrote into the index, and answer 200 with `applied` true, so
  that the next read of the library shows the containers. It SHALL NOT walk the library.

The route SHALL require the operator's bearer, as every route that writes does; a missing or wrong
bearer SHALL be 401.

#### Scenario: a series made at the top of an empty library
- **WHEN** the operator creates a series, one of its seasons and one serial of that season in a
  library with nothing in it, with no parent
- **THEN** the answer is 200 with `applied` true and three new sidecars, and the library's
  containers answer the series, with the season and the serial beneath it and no presentations

#### Scenario: a season made beneath a series the library holds
- **WHEN** the operator creates a season beneath a series the library holds, whose own fields name
  the season as a child
- **THEN** the season's sidecar is new, the series' sidecar is updated with the season's path alone,
  and the series' presentations and own fields are as they were

#### Scenario: a container the library already holds
- **WHEN** a request carries a serial the library already holds, beneath a season it does not
- **THEN** the answer is 422 with the finding that the serial is already at its folder, and nothing
  is written

#### Scenario: a parent that does not name the top
- **WHEN** a season is created beneath a series the library holds, and the series' sidecar does not
  name the season as a child
- **THEN** the answer is 422 with the finding that the series does not name the season, and nothing
  is written

#### Scenario: a dry run
- **WHEN** a request that would apply is posted with `dryRun` true
- **THEN** the answer is 200 with `applied` false and the writes it would make, and the library is
  unchanged

#### Scenario: a placement into a container made this way
- **WHEN** a serial has been created with no presentations, and a presentation of one of its parts
  is then placed with a lineage carrying a different title for the serial
- **THEN** the serial's sidecar keeps the title it was created with, and holds the presentation

#### Scenario: a create without the operator's bearer
- **WHEN** a create is posted with no `Authorization` header
- **THEN** the answer is 401

Pinned by: `Tests/SiloTests/ServerTests.swift` (`containersAreMadeInALibraryWithoutAFile`).
