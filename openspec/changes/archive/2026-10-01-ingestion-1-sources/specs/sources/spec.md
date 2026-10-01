<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A source is registered with its input spec, and the silo mints its id
`POST /v1/sources` with an input spec, an optional natural key, and an optional copy SHALL register
a source and answer 201 with it: an `id` the silo mints, a lowercased UUID; the input spec as given;
the natural key; and its copies. An input spec the silo refuses, as
[input-specs](../input-specs/spec.md) describes, SHALL be 400 with the reason, and register
nothing. The route SHALL be behind the operator's token. The silo SHALL keep each source as one JSON
file under its state directory, so the sources it has survive a restart.

#### Scenario: a source registered
- **WHEN** the operator registers a source with a valid input spec and a copy on node `ripper`
- **THEN** the answer is 201 with a minted id, the spec, and one copy on `ripper`

#### Scenario: a source the spec refuses
- **WHEN** the operator registers a source whose input spec repeats a stream index
- **THEN** the answer is 400 naming the index, and no source is registered

Pinned by: nothing yet.

### Requirement: A natural key finds the source already registered
A natural key SHALL be a `scheme` and a `value`, both text, unique among the silo's sources.
Registering a source whose natural key matches one the silo has SHALL answer 200 with the existing
source, adding the copy given if it is not already one of its copies; registering one whose natural
key matches but whose input spec differs SHALL be 409, changing nothing. A source registered
without a natural key SHALL never be matched.

#### Scenario: the same disc title twice
- **WHEN** a source is registered with natural key scheme `discTitle` and value `3F1AC2E9/00004`, and
  registered again with the same key and spec and a copy on another node
- **THEN** the second answer is 200 with the first source's id, which now has both copies

#### Scenario: the same key, a different description
- **WHEN** a source is registered again with a matching natural key and an input spec with one more
  audio stream
- **THEN** the answer is 409, and the source is as it was

Pinned by: nothing yet.

### Requirement: A source's copies say where its file is, and a source may have none
A copy SHALL be a node and the file reference that node serves the source's file by: its holder,
URL, local path, size and secret, as [jobs](../jobs/spec.md) describes a file reference.
`POST /v1/sources/{id}/copies` SHALL add a copy and `DELETE /v1/sources/{id}/copies/{node}` SHALL
remove the copy that node holds, both behind the operator's token, and an unknown source SHALL be
404. A source whose last copy is removed SHALL be kept.

#### Scenario: the last copy goes
- **WHEN** a source's only copy is removed
- **THEN** the source is still registered, with no copies

Pinned by: nothing yet.

### Requirement: Sources are read openly
`GET /v1/sources` SHALL answer every source and `GET /v1/sources/{id}` one, or 404 for an id the
silo does not know, with no token asked. A copy's secret SHALL NOT be in either answer: it is handed
only to a node that claims a job needing the file.

#### Scenario: a source read without its secrets
- **WHEN** a client reads a source with a copy, without a token
- **THEN** the answer carries the copy's holder and URL and no secret

Pinned by: nothing yet.
