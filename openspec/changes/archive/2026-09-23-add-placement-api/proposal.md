<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Add placement through the server

**Retrospective archive — merged 2026-09-23 as pull request #4.** This change predates the
corpus; its documents were reconstructed from the merge afterwards.

## Why

Pull request #2 delivered the local placement engine, and the operator's command line already
places a file into a library by hand. But the pipeline the design is building towards ends in
the library, and until the silo itself answers "place this", no later work can reach that end:
the jobs that follow need the server to take a finished file, write it into the library and
learn of it. This is the "Placement through the server" step of the proposal's build order, on
top of the read path pull request #3 merged.

## What Changes

- A new operation, `placeFile` at `POST /v1/libraries/{library}/place`, on the operator
  controller — so it sits behind the same operator-token gate as scanning and ruleset storage,
  and a request without the token is answered 401. A library the silo does not serve is a 404.
- The request body names the container the item is in and every container above it, root first,
  each as its repository XML document, together with the item, an optional alternative, profile,
  track and chapter mappings and source, and the file as a path the silo can reach. A container
  document that cannot be read, a lineage that does not hold together, or an item the container
  does not have is answered 400 with a problem detail.
- Nothing is written before the placement is shown: the answer carries the declared write
  targets, one per line, and the findings, and a request marked `dryRun` returns exactly that
  with `applied` false and no file touched. A placement a finding refuses — a destination that
  already exists among them — is answered 409 with the same body, and nothing moves.
- On apply the file is moved into place (copied when asked), and the server then re-reads the
  library into its index itself — an incremental scan, an unchanged sidecar costing a stat, so
  the placed presentation is served by the media route at once, without a scan being requested,
  and the answer carries the presentation's id.
- Supporting: `LibraryWalker.relativePath(of:in:)` becomes public so the route can report the
  destination relative to the library root, and the index opens its SQLite file with a
  five-second busy timeout so the operator's command line and the silo can share one index file.

## Impact

- Affected specs: placement, index-and-rulesets
- Affected code: `Sources/SiloAPI/openapi.yaml` (the `/libraries/{library}/place` path and the
  `PlaceRequest`/`PlacementResult` schemas), `Sources/SiloApp/OperatorController.swift` (the
  `placeFile` operation), `Sources/SiloApp/Mapping.swift` (the `BadPlacement` and
  `PlacementRefused` errors), `Sources/SiloLibrary/LibraryWalker.swift` (visibility),
  `Sources/SiloStore/Index.swift` (the busy timeout), `Tests/SiloTests/ServerTests.swift` (the
  placement server test and the fixture reshaping it needed).
