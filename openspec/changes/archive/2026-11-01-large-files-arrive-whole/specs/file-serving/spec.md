<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A file is answered whole however long it is
A holder's file server SHALL read each request to its end before answering it, discarding any body,
so that the connection outlives the response: a file longer than the socket buffer SHALL arrive with
every byte its `Content-Length` names. A body longer than a mebibyte SHALL be read no further, and its
connection closed once the answer is sent.

#### Scenario: a large file fetched again and again
- **WHEN** a published three-mebibyte file is fetched thirty times with its secret
- **THEN** each answer is the whole file

Pinned by: `Tests/SiloTests/FileServerTests.swift` (`aLargeFileArrivesWholeEveryTime`). The silo's own
routes, the media route among them, are served through wire-mvc, which reads what a route leaves of its
request; that is pinned by wire-mvc's own live-server test (swift-wire/wire-mvc#257).
