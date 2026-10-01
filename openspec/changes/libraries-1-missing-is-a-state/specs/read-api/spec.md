<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The libraries are listed, with what they hold
`GET /v1/libraries` SHALL answer 200 with one object per configured library —
its `id`, the count of `containers` under its roots, the count of
`presentations` across those containers, walked the whole tree down, and
whether it is `available`.

#### Scenario: the one library and its counts
- **WHEN** a client asks `GET /v1/libraries`
- **THEN** the 200 answer names `"id":"main"`, counts `"presentations":2`, and
  reads `"available":true`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`).

## ADDED Requirements

### Requirement: An unavailable library is kept, and says so
A library SHALL be unavailable while its folder does not exist, or while its last walk found no
container at its top level where the index holds containers for it. While a library is unavailable
the silo SHALL keep its index rows, SHALL list it with `"available":false`, and SHALL answer its media
route with 503. The silo SHALL log each change of a library's availability once. The boot SHALL NOT
stop for an unavailable library.

#### Scenario: a drive that is not there
- **WHEN** the silo boots with a library's folder missing
- **THEN** it serves every other library, lists that one unavailable, keeps its containers
  browsable, and answers 503 for its presentations

Pinned by: nothing yet.
