<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A held container's tree is reviewed against TMDb as a walk, a container at a time
Opening a held container's differences SHALL start a walk rooted at it, whose first stop is the
container. Confirming a stop SHALL be the operator saying it is as it should be, so that the walk need not come
back to it before it is stored: it SHALL keep its chosen differences as the container's pending change, and
SHALL add as pending stops beneath it each container the library holds beneath it, and each new one,
in the order its children list them, whatever their ids: a series' seasons in TMDb's order, a held
container's other children each at its place among its missing episodes, and a new container's in
its draft's order; a stop never read SHALL add them in the order its sequences hold them. A stop confirmed with nothing chosen and nothing placed in it SHALL be confirmed and unchanged. Pending stops
SHALL be opened in the tree's order, depth first; open on the first of them, the operator SHALL be
able to confirm it and open the next in one step. Closing the walk SHALL say that it saves the walk
on this Mac. The console SHALL show the walk's tree as far as the
walk has found it, each stop with its state, which SHALL say what storing the walk would do: pending, not confirmed; or
confirmed, and then that storing creates its container, creates it only once a stop above it named
there is confirmed, edits it, or leaves it unchanged, as the store would find it. The operator SHALL
be able to open any stop of the walk, and a confirmed stop SHALL open with its choices and placements
as they were left. Any change to a confirmed stop's choices, a difference ticked or unticked, its
missing episodes grouped, ungrouped, titled or put into a container held beneath it, a special placed
in it or taken from it, an alternative drafted for it changed, or its draft shaped, SHALL make it pending again with its choices kept, and so
SHALL unconfirming it; a change to the missing episodes put into a held container SHALL make that
container's stop pending too. Confirming a stop again SHALL replace its pending change. When the walk's root is a
series, or is beneath one, the series' unassigned specials SHALL be shown beside every stop with their
suggestions. A special suggested for the open stop SHALL be marked as suggested there only on
something that ties it there: its title naming the stop, an entry of it, the story TMDb titles an
entry a part of, or a container beneath it; or smddb filing it there. A series' own title, which any
of its specials may carry, SHALL tie nothing. A special SHALL be
placeable in the open stop, as an entry in a sequence of it at a position or as one of its extras, and
anywhere a draft's specials may be placed. A special SHALL be draggable onto the open stop's alternatives: onto
their heading, to draft an alternative playing it alone; onto an entry of a drafted alternative, to
play in its place; or between two of its entries, to be added there. Each of the stop's sequences, the first from
its children's heading, and each drafted alternative SHALL offer to be cloned into a drafted
alternative, a drafted alternative's entries SHALL be reordered by
dragging them, and a special SHALL be draggable onto the stop's extras by kind, and among its children, placed in
its primary sequence before the child it is dropped on or past the last: in a held stop listed there
and moved there as the operator would move it, one placed there already moved, and in a new stop at
that entry's position in its draft, listed there among its children. The operator SHALL be able to rename a stop's primary
sequence, the name kept as a sequence id and refused when another of its sequences has it; the
alternatives naming it and the specials placed in it SHALL be renamed with it, a new stop's draft
SHALL be shaped with it, and a held stop's SHALL be renamed by its edit when the walk is stored. When
the operator says, the primary sequence of each container beneath the stop the walk knows, those its
container lists and the stops beneath it at any depth, SHALL be renamed too, a held one not yet read
when its edit is made, and each SHALL refuse the name alone when another of its sequences has it. A placed special SHALL leave the unassigned specials and
become part of the pending change of the container it was placed in, and removing it from that change
SHALL return it. A stop SHALL show, pending or confirmed, the alternatives storing the walk would
leave its container with: those it holds or its draft has, then those the specials placed in it make,
each with its title and what it plays, in order, by title. What it shows SHALL be what storing creates. A stop never opened or left pending, and a special never placed, SHALL change nothing.

Nothing SHALL be stored until the operator stores the walk. Before storing, the console SHALL list
every creation, edit and artwork put the walk makes, in the order it will make them: the companion
series it makes at the top of the library; the edits that specials placed elsewhere make of containers
outside the walk, so that what the walk's edits refer to is there; each changed container's edit, in
the tree's order, each followed by the creation of the containers it names beneath it, since a
container is created beneath a parent only once the parent names it; and the artwork. An edit a
placement makes of a container that is a confirmed stop SHALL be part of that stop's edit. Storing
SHALL make them in that order and stop at the first refusal, saying what was stored and what was not,
and the walk SHALL keep what was not.

#### Scenario: a series confirmed with nothing chosen
- **WHEN** a held series holding three seasons, each holding serials, is confirmed with nothing chosen
- **THEN** the series is confirmed and unchanged, its three seasons are pending in TMDb's order, and
  confirming the first season makes its serials pending ahead of the second season

#### Scenario: a special placed where it belongs
- **WHEN** one of a series' unassigned specials is placed as an entry of a season while the season's
  stop is open, and the walk is stored
- **THEN** the season's edit adds an entry carrying the special's references, and the special is no
  longer unassigned

#### Scenario: a special suggested where it aired
- **WHEN** a special is suggested for a season for when it aired alone, and another, titled as the
  making of a serial beneath the season, is suggested for the season too
- **THEN** only the second is marked as suggested there

#### Scenario: a stop opened again
- **WHEN** a confirmed season is opened again from the walk's tree, one more difference is chosen, and
  the season is confirmed again
- **THEN** its earlier choices are shown as they were left, and its pending change holds both
  differences

#### Scenario: a walk stored before its end
- **WHEN** a walk is stored with stops it never opened
- **THEN** only the confirmed stops' changes are stored

#### Scenario: a refusal part of the way through
- **WHEN** the silo refuses the second of a walk's three edits
- **THEN** the first is stored, the second and third are not, and the walk keeps the second and third

#### Scenario: a held series' seasons in TMDb's order
- **WHEN** a held series' sequence holds its seasons out of TMDb's order, and its stop is confirmed
- **THEN** its seasons are queued beneath it in TMDb's order

#### Scenario: a confirmed stop changed
- **WHEN** a confirmed season's stop has a special placed in it
- **THEN** the stop is pending again with the special placed, and storing the walk stores nothing of
  it until it is confirmed again

#### Scenario: alternatives a placed special makes
- **WHEN** a serial's stop holding one alternative has one special placed as another version of its
  first episode and another as another version of the serial, before the stop is confirmed
- **THEN** the stop shows the alternative it holds, then one playing the first special in place of the
  first episode followed by the serial's other episodes, then one playing the second special alone,
  each marked as made by a placed special, and storing the walk makes those alternatives

#### Scenario: a primary sequence renamed
- **WHEN** a held serial's primary sequence, which a special is placed in, is renamed, and the walk is
  stored
- **THEN** the serial's edit renames the sequence, and the special's entry is in it

#### Scenario: a special dropped among a held stop's children
- **WHEN** a special is dropped on the third of a held serial's four parts at its stop, and another
  past the last
- **THEN** the first is listed among the serial's children before the third part, and the other last

#### Scenario: a ticked difference ticked again
- **WHEN** a difference a confirmed stop has ticked is ticked again
- **THEN** the stop stays confirmed

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`confirmingAStopQueuesTheContainersBeneathItInTheTreesOrder`,
`aStopsChildrenAreInTheOrderItsChildrenListThem`, `anyChangeToAConfirmedStopMakesItPendingAgain`,
`aSpecialPlacedAtAStopIsStoredInThatContainersEdit`, `aConfirmedStopOpenedAgainKeepsWhatWasChosen`,
`aWalkStoresOnlyWhatWasConfirmed`, `aWalksStoreStopsAtTheFirstRefusal`,
`anEditOfAConfirmedStopIsPartOfThatStopsEdit`, `aSpecialIsSuggestedHereOnlyWhenItsTitleTiesItThere`,
`aStopShowsTheAlternativesItsPlacedSpecialsMake`,
`aHeldStopsSequencesAreRenamedWhenStored`, `aNewStopsSequenceIsRenamedInItsDraft`,
`aStopsPrimarySequenceIsRenamedBeneathItAndGivenToItsGroups`,
`aRegroupedContainersPrimarySequenceIsItsParentsAndRenamedBeneathIt`,
`aNewStopShowsTheAlternativesItsPlacedSpecialsMake`,
`aSpecialDroppedAmongAStopsChildrenIsPlacedBeforeTheChild`). The walk's sheet is pinned by nothing yet, as the rest
of the shell is, but for what its alternatives read from a drop: `Tests/SiloAdminTests/AlternativesEditorTests.swift`
(`aDragIsReadBackFromItsText`).
