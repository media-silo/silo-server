<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A container is served as its sidecar
`GET /v1/containers/{id}/smd` SHALL answer 200 with the sidecar's bytes
exactly as the index recorded them, with `Content-Type`
`application/xml; charset=utf-8` and the document's `Content-Length`. A
container the index does not hold SHALL be 404.

#### Scenario: the bytes as they are on disk
- **WHEN** a client asks `GET /v1/containers/0000000000000003/smd`
- **THEN** the 200 answer's body equals, byte for byte, the library's
  `Doctor Who (1963)/01 - Pyramids of Mars/container.smd`, and
  `GET /v1/containers/00000000000000ff/smd` is 404

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theSidecarIsServedAsItIs`).
