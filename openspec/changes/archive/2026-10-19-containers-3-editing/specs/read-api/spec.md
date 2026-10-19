<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A container's own fields are edited in one library, on the sidecar the editor read
`PUT /v1/libraries/{library}/containers/{id}` with a JSON `ContainerEdit` — `document`, the
container as its repository XML; `basedOn`, the digest of the sidecar it was made from; and
`dryRun` — SHALL set the container's own fields in that library's sidecar to the document's,
and SHALL change none of the library's facts: its presentations, its children's `smd` paths and
its rules stay as they stand. A sidecar's digest is the SHA-256 of its bytes as the index read
them, in lowercase hexadecimal, and the `LibraryContainer` a library's container route answers
SHALL carry it as `digest`. The answer SHALL be a `ContainerEditResult`: `applied`, the
sidecar's bytes as written or as they would be, their `digest`, and the `findings`.

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
- Otherwise the silo SHALL write the sidecar, re-read it into the index, and answer 200 with
  `applied` true, so that the next read of the container shows the edit.

The route SHALL require the operator's bearer, as every route that writes does; a missing or
wrong bearer SHALL be 401.

#### Scenario: a title corrected
- **WHEN** the operator puts a container's document with its year changed from 1997 to 1979,
  based on the digest the library's container route answered
- **THEN** the answer is 200 with `applied` true, the library's container reads the year 1979,
  and its presentations, its children's paths and its rules are as they were

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

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aContainersOwnFieldsAreEditedOntoTheSidecarRead`).
