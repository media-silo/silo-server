<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A walk is kept on this Mac until it is stored or discarded
A walk SHALL be kept on this Mac, with its stops, their states, choices and placements, and the series'
unassigned specials, until it is stored or the operator discards it. Opening the differences of a
container that roots a kept walk SHALL offer to resume the walk or start again. The silo SHALL hold
nothing of a walk. An edit whose sidecar has changed since its stop read it SHALL be refused as a stale
edit is, the store SHALL stop there, and the stop SHALL be read again.

#### Scenario: a walk resumed
- **WHEN** a walk with two confirmed stops and one placed special is kept, and the console is opened
  again
- **THEN** resuming the walk shows the same stops, states, choices and placement

#### Scenario: a walk discarded
- **WHEN** a kept walk is discarded
- **THEN** opening its root's differences starts a new walk

#### Scenario: a sidecar changed behind the walk
- **WHEN** a stop's sidecar changes in the library after the stop was read, and the walk is stored
- **THEN** that stop's edit is refused, the store stops there and says so, and the stop is read again

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aWalkIsKeptOnThisMacAndResumed`,
`aDiscardedWalkIsGone`, `aStopWhoseSidecarChangedIsReadAgain`). The offer to resume is pinned by
nothing yet, as the rest of the shell is.
