<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A library holds a container once
A library SHALL hold at most one sidecar for a container. When the walk reaches a sidecar naming
a container it has already found in the same library, it SHALL report that sidecar as an
error-severity finding, `container <id> is already at "<path>"`, naming the folder of the one
found first relative to the library root, and SHALL NOT index it. The walk SHALL NOT decide
which of the two is right. The same container in another library is not a second sidecar.

#### Scenario: one container filed twice in a library
- **WHEN** a library's `Alien (1979)` and `Alien` folders each hold a sidecar for one
  container, and the walk reaches `Alien` first
- **THEN** the walk reports an error on `Alien (1979)/container.smd` saying the container is
  already at `Alien`, and the index holds the container as `Alien` alone

Pinned by: `Tests/SiloStoreTests/IndexTests.swift` (`aContainerFiledTwiceInALibraryIsReportedOnce`).
