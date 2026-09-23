<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Each job route sits behind the gate its audience holds
The two read routes SHALL ask no token. The routes the operator's side speaks — register, assign,
cancel, retry and place — SHALL be behind the operator's configured bearer token, and a silo with
no token configured SHALL refuse them all. The four a node speaks — claim, progress, complete and
fail — SHALL be behind the node gate, which the operator's token also passes, so the embedded node
and the operator's own tooling need nothing more. The node gate and the node token it accepts are
the [node-discovery](../node-discovery/spec.md) capability's.

#### Scenario: the operator's token passes the node gate
- **WHEN** a client claims with `Authorization: Bearer <operator token>`
- **THEN** the claim is answered 200, as the embedded node's would be

Pinned by: `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`).

