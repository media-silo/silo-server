<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Tasks

**Retrospective archive — every task was completed in pull request #4 (merged 2026-09-23).**

## 1. API surface

- [x] 1.1 Add `POST /libraries/{library}/place` (`placeFile`) to `Sources/SiloAPI/openapi.yaml`,
  operator-gated, with 200, 400, 401, 404 and 409 responses, plus the `PlaceRequest` and
  `PlacementResult` schemas — the request requiring `containers`, `item` and `file`; the result
  carrying `applied`, `destination`, `presentation`, `writes` and `findings`

## 2. The operation

- [x] 2.1 Add the `BadPlacement` (400, as a problem detail) and `PlacementRefused` (409, carrying
  the result) errors to `Sources/SiloApp/Mapping.swift`
- [x] 2.2 Add `placeFile` to `OperatorController`: parse the lineage documents, build the
  `PlacementRequest`, compute the placement, refuse the inapplicable, honour `dryRun`, apply
  (moving unless `copy` asks otherwise), scan the library into the index, and answer the result
  with the presentation's id
- [x] 2.3 Make `LibraryWalker.relativePath(of:in:)` public, and open the index's SQLite file
  with a five-second busy timeout so the operator's command line and the silo can share one
  index file

## 3. Tests

- [x] 3.1 Reshape `Fixture` in `Tests/SiloTests/ServerTests.swift` so a root is built per suite
  and the environment (including the operator token) is derived from it
- [x] 3.2 Add `zPlacementIsShownThenAppliedAndRefusedTheSecondTime`, placed last in the suite on
  purpose: 401 without the token, the dry-run show, apply and serve without a requested scan,
  409 on the repeated placement, 400 on an unknown item and on an unreadable document, and 404
  on an unknown library
