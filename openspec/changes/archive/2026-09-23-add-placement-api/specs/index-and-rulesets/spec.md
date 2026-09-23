<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A placement the server applies brings the index up to date itself
After the server applies a placement it SHALL bring the index up to date itself, by an
incremental scan of the library, so the placed presentation is indexed and served without
a scan being requested. An unchanged sidecar costs a stat, so the whole library is
re-walked rather than only the container the placement rewrote; `Indexer.refresh` remains
the one-container entry point.

#### Scenario: a placed presentation is served without a requested scan
- **WHEN** `POST /v1/libraries/main/place` applies a placement for item `part2`
- **THEN** `GET /v1/media/{presentation}` for the answer's presentation id answers 206, and
  `GET /v1/containers/0000000000000003` shows the placed `Part Two.mkv` at once

Pinned by: `Tests/SiloTests/ServerTests.swift` (`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).

