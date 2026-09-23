<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Tasks

**Retrospective archive — every task was completed in pull request #3 (merged 2026-09-23).**

## 1. The index

- [x] 1.1 Add `SiloStore`: the SQLite index, one table per sidecar element plus the sidecar
      table, the container row carrying the sidecar's bytes
- [x] 1.2 Add the incremental scan — re-parse only sidecars whose time or size changed, take
      unchanged containers' children from the index, remove what the walk no longer reaches
- [x] 1.3 Add the rulesets store: verbatim documents under `rulesets/<name>/<version>.xml`,
      versions numbered under one lock, never rewritten

## 2. The read path

- [x] 2.1 Add `SiloAPI`: the OpenAPI document under `/v1` and its generator wiring
- [x] 2.2 Add the library, media, operator and ruleset controllers with the sidecar's
      elements as JSON; profile as a filter that never substitutes
- [x] 2.3 Add the two streaming routes: the presentation's file by `Range` (206/416, `ETag`,
      `Accept-Ranges`) and the container as its sidecar

## 3. The server

- [x] 3.1 Add `SiloApp` wiring and the `silo` executable: environment configuration, boot
      scan, operator-token middleware on the mutation routes
- [x] 3.2 Test in-process (`IndexTests`, `ServerTests`) against a real library the placer
      built, and exercise a real socket: the listing, a 1024-byte range, the whole file byte
      for byte, and the gate
