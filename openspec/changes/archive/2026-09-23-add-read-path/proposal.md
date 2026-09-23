<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Add the silo: the index, the read path, rulesets, and media by range

**Retrospective archive — merged 2026-09-23 as pull request #3.** This change predates the
corpus; its documents were reconstructed from the merge afterwards.

## Why

The rules engine and the library layer made files and filed them, but nothing answered a
client. The proposal's discovery half — the read path of `Hosting.md` turned to face one
household's library — needed a server: requests answered from an index rather than by parsing
sidecars on the way, and the two routes that stream served beside the OpenAPI document.

## What Changes

- The index: one SQLite file in the state directory, one table per sidecar element plus a
  sidecar table recording modification time and size; a scan re-parses only what changed; the
  container row keeps the sidecar's bytes; the file can be deleted and is rebuilt.
- The read API: an OpenAPI document under `/v1` for libraries, the listed roots, one container
  with its presentations and children, lookup by provider id, search, rulesets and a dry run
  of the resolver; two streaming routes beside it — the presentation's file with `Range`,
  `ETag` and `Accept-Ranges`, and the container as its sidecar.
- The rulesets store: documents kept verbatim under `rulesets/<name>/<version>.xml`, every
  store a new version the silo numbers, a version never rewritten; mutation routes sit behind
  the operator's bearer token.
- A profile query filters a container's presentations and never substitutes one — principle
  8 made a test.
- The server itself: `Sources/SiloApp` controllers on the wire stack, a composition root, and
  environment configuration (`SILO_LIBRARIES`, `SILO_STATE_DIR`, `SILO_OPERATOR_TOKEN`); tested
  in-process against a real library the placer built, and over a real socket.

## Impact

- Affected specs: index-and-rulesets, read-api
- Affected code: Sources/SiloStore, Sources/SiloAPI, Sources/SiloApp, Sources/silo,
  Tests/SiloStoreTests, Tests/SiloTests
