<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The libraries are listed, with what they hold
`GET /v1/libraries` SHALL answer 200 with one object per configured library —
its `id`, the count of `containers` under its roots, the count of
`presentations` across those containers, walked the whole tree down, and
whether it is `available`, and whether it is `walking`: true while a walk of it is under way, its
first after it was added or any other.

#### Scenario: the one library and its counts
- **WHEN** a client asks `GET /v1/libraries`
- **THEN** the 200 answer names `"id":"main"`, counts `"presentations":2`, and
  reads `"available":true`

#### Scenario: a library being walked
- **WHEN** a client lists the libraries while one of them is walked
- **THEN** that library reads `"walking":true`, and the others `"walking":false`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`). A library listed `walking`
is pinned by nothing yet.
