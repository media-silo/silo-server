<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A walk's store is handed to the silo whole, under a key kept with the walk
Storing a walk SHALL send the silo one store of the steps the walk's list says, in its order, under a
key the console chooses and keeps with the walk before the store is sent, after putting each image the
store puts that the silo does not already hold. Each edit SHALL be a document on the base its stop, or
the list, read: a placement's edit of a container that is not a stop, the refs declined in a series and
a drafted record's naming in the collection holding it SHALL be read when the list is made, and every
edit the walk makes of one container SHALL be one step. A walk with a key SHALL ask after its store,
and SHALL NOT send it again, until the silo says the store is made or refused: a store made SHALL mark
every step of the walk stored, and a store refused SHALL mark the steps before the one refused stored,
keep the rest, and free the key, so that the walk's next store is sent under a new one. An edit of a
container an earlier step of the store makes SHALL be sent with an empty base, to be made on what that
step made.

#### Scenario: a store whose answer never arrived
- **WHEN** a walk's store is sent and its answer is lost, and the operator stores the walk again
- **THEN** the console asks after the walk's key rather than sending the store again, and each step is
  made once

#### Scenario: a placement in a container that is not a stop
- **WHEN** a special is placed in a container the walk does not visit, and the walk is stored
- **THEN** the store edits that container with the special placed, on the base the list read

#### Scenario: a store refused part of the way through, stored again
- **WHEN** a walk's store of three steps is refused at its second, and the operator stores the walk
  again once the refusal is answered
- **THEN** the second store is sent under a new key with the second and third steps alone

#### Scenario: specials declined in a series the walk makes
- **WHEN** a walk makes a series and declines one of its specials, and the walk is stored
- **THEN** the store makes the series, and then edits it with an empty base to decline the special

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aStoreWhoseAnswerNeverArrivedIsAskedAfter`,
`aSpecialIsPlacedInACompanionSeriesTheLibraryHolds`, `aWalksStoreStopsAtTheFirstRefusal`,
`aRecordTheLibraryLacksIsWalkedFromADraft`).

## MODIFIED Requirements

### Requirement: A walk is kept on this Mac until it is stored or discarded
A walk SHALL be kept on this Mac, with its stops, their states, choices and placements, and the series'
unassigned specials, until it is stored whole or the operator discards it. Opening the differences of a
container that roots a kept walk SHALL offer to resume the walk or start again. The silo SHALL hold
nothing of a walk but the record of its store. An edit whose sidecar has changed since its stop, or the
list, read it SHALL refuse the store before any of it is made, the console SHALL say so, and the stop
SHALL be read again and be pending, its choices kept, until the operator confirms it again.

#### Scenario: a walk resumed
- **WHEN** a walk with two confirmed stops and one placed special is kept, and the console is opened
  again
- **THEN** resuming the walk shows the same stops, states, choices and placement

#### Scenario: a walk discarded
- **WHEN** a kept walk is discarded
- **THEN** opening its root's differences starts a new walk

#### Scenario: a sidecar changed behind the walk
- **WHEN** a stop's sidecar changes in the library after the stop was read, and the walk is stored
- **THEN** the store is refused before any of it is made and says that stop's edit was, and the stop is
  read again

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aWalkIsKeptOnThisMacAndResumed`,
`aDiscardedWalkIsGone`, `aStopWhoseSidecarChangedIsReadAgain`). The offer to resume is pinned by
nothing yet, as the rest of the shell is.

### Requirement: A walk's store says each step as it goes
While SiloAdmin stores a walk, the console SHALL first say the images it is sending, with how many,
and then the step of the plan being made, as the plan describes it, and how many of the plan's steps
are made before it, as the store's record at the silo says them, asked after every second. A store the silo refuses SHALL say
no step past the one refused. While the store is under way, the console SHALL take neither a second
store nor the operator putting the store off.

#### Scenario: a store refused part of the way through
- **WHEN** a walk of three edits is stored, and the silo refuses the second
- **THEN** the first edit is said as begun with none of three made, the second with one of three made,
  and the third is never said

#### Scenario: a walk opened while its store is under way
- **WHEN** the console quits while a walk's store is under way at the silo, and the walk is opened again
- **THEN** the store's step is said as the silo's record says it, and the store is not sent again

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aWalksStoreStopsAtTheFirstRefusal`,
`aWalkKeptWhileItsStoreIsUnderWayAsksAfterIt`). The sheet's showing it is pinned by nothing yet, as the
rest of the shell is.
