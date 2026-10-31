<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A walk's store says each step as it goes
While SiloAdmin stores a walk, the console SHALL show the step of the plan being made, as the plan
describes it, and how many of the plan's steps are made before it. A store the silo refuses SHALL say
no step past the one refused. While the store is under way, the console SHALL take neither a second
store nor the operator putting the store off.

#### Scenario: a store refused part of the way through
- **WHEN** a walk of three edits is stored, and the silo refuses the second
- **THEN** the first edit is said as begun with none of three made, the second with one of three made,
  and the third is never said

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aWalksStoreStopsAtTheFirstRefusal`).
The sheet's showing it is pinned by nothing yet, as the rest of the shell is.
