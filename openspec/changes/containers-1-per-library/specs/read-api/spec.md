<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: One container answers with its presentations
`GET /v1/containers/{id}` SHALL answer 200 with the container and, for every
item in its sequences and extras, the presentations the index holds for that
item — the same presentations the media route takes, by id, stable across
rescans. A container the index does not hold SHALL be 404. A container held by
more than one library SHALL be answered as the first of them in the order
`settings.json` lists the libraries holds it — its sidecar and that library's
presentations — and the answer SHALL name that `library`.

#### Scenario: the serial and its presentations
- **WHEN** a client asks `GET /v1/containers/0000000000000003`
- **THEN** the 200 answer's sequences list the serial's three parts, each part
  an item with its presentations

#### Scenario: a container in two libraries
- **WHEN** `settings.json` lists `films` before `films-4k`, each holds a sidecar
  for one container, and a client asks for the container
- **THEN** the 200 answer names `films` as its library and carries the
  presentations `films` holds and not those `films-4k` holds

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`). The
answer for a container in several libraries is pinned by nothing yet.

## ADDED Requirements

### Requirement: A library's containers are read within the library
`GET /v1/libraries/{library}/containers` SHALL answer 200 with a
`ContainerSummary` for each container at the top of the library, listed or not.
`GET /v1/libraries/{library}/containers/{id}` SHALL answer 200 with a
`LibraryContainer`: the `library`, and the `container` as the library's own
sidecar says it, with that library's presentations, in the form
`GET /v1/containers/{id}` answers. `GET /v1/libraries/{library}/containers/{id}/smd`
SHALL answer the library's sidecar bytes as `GET /v1/containers/{id}/smd` answers
a sidecar. Each SHALL be 404 for a library the silo does not serve and for a
container the library does not hold, whether or not another library holds it.
These are read routes, and SHALL answer without a token.

#### Scenario: an unlisted container at the top of a library
- **WHEN** a library's top-level folders hold a listed series and an unlisted one, and a
  client asks for the library's containers
- **THEN** the 200 answer carries both, where `GET /v1/containers` carries the listed one
  alone

#### Scenario: each library's own view
- **WHEN** `films` and `films-4k` each hold a sidecar for one container, and a client asks
  each library for it
- **THEN** each answer names its own library and carries that library's presentations

#### Scenario: a container another library holds
- **WHEN** a client asks `films` for a container only `films-4k` holds
- **THEN** the answer is 404

Pinned by: nothing yet.
