<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Applying a placement moves the file and tells the index
Unless `dryRun`, an applicable placement SHALL be applied and answered 200 with `applied` true
and `presentation` set to the placed presentation's id — what the media route takes. The file
is moved into place: it no longer exists where it was. After applying, the server SHALL
re-read into its index each sidecar the placement wrote, as [index](../index/spec.md) sets
out, so the placed presentation is indexed and served without a scan being requested; it
SHALL NOT walk the library.

#### Scenario: an applied placement moves the file into place
- **WHEN** the same body is sent with `dryRun: false`
- **THEN** the answer is 200 with `applied` true and a `presentation` id, and the file no
  longer exists at its original path

#### Scenario: the placed presentation is served without a requested scan
- **WHEN** `GET /v1/media/{presentation}` is asked for `bytes=0-9` of the answer's id
- **THEN** the answer is 206, and `GET /v1/containers/0000000000000003` shows the file
  `Part Two.mkv` and its chapter titled `Opening`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).
