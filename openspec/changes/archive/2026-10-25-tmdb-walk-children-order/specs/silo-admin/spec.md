<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A held container's tree is reviewed against TMDb as a walk, a container at a time
Opening a held container's differences SHALL start a walk rooted at it, whose first stop is the
container. Confirming a stop SHALL keep its chosen differences as the container's pending change, and
SHALL add as pending stops beneath it each container the library holds beneath it, and each new one,
in the order its children list them, whatever their ids: a series' seasons in TMDb's order, a held
container's other children each at its place among its missing episodes, and a new container's in
its draft's order; a stop never read SHALL add them in the order its sequences hold them. A stop confirmed with nothing chosen and nothing placed in it SHALL be confirmed and unchanged. Pending stops
SHALL be opened in the tree's order, depth first. The console SHALL show the walk's tree as far as the
walk has found it, each stop with its state: pending, open, changed, or looked at. The operator SHALL
be able to open any stop of the walk, and a confirmed stop SHALL open with its choices and placements
as they were left; confirming it again SHALL replace its pending change. When the walk's root is a
series, or is beneath one, the series' unassigned specials SHALL be shown beside every stop with their
suggestions. A special suggested for the open stop SHALL be marked as suggested there only on
something that ties it there: its title naming the stop, an entry of it, the story TMDb titles an
entry a part of, or a container beneath it; or smddb filing it there. A series' own title, which any
of its specials may carry, SHALL tie nothing. A special SHALL be
placeable in the open stop, as an entry in a sequence of it at a position or as one of its extras, and
anywhere a draft's specials may be placed. A placed special SHALL leave the unassigned specials and
become part of the pending change of the container it was placed in, and removing it from that change
SHALL return it. A stop never opened, and a special never placed, SHALL change nothing.

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

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`confirmingAStopQueuesTheContainersBeneathItInTheTreesOrder`,
`aStopsChildrenAreInTheOrderItsChildrenListThem`,
`aSpecialPlacedAtAStopIsStoredInThatContainersEdit`, `aConfirmedStopOpenedAgainKeepsWhatWasChosen`,
`aWalkStoresOnlyWhatWasConfirmed`, `aWalksStoreStopsAtTheFirstRefusal`,
`anEditOfAConfirmedStopIsPartOfThatStopsEdit`, `aSpecialIsSuggestedHereOnlyWhenItsTitleTiesItThere`). The walk's sheet is pinned by nothing yet, as the rest
of the shell is.

### Requirement: A missing child chosen in a walk is a new container, created when the walk is stored
A missing child chosen at a stop of a walk SHALL join the walk, when the stop is confirmed, as a new
stop beneath it: a draft from TMDb, read as a draft from TMDb reads it, with ids from smddb's client.
It SHALL be drafted once, however many times the stop is confirmed, and the console SHALL take no
second confirm of a stop while one is under way. The walk's tree SHALL show it as new. Its fields and
references, and any artwork TMDb offers for it, SHALL be chosen to begin with. It SHALL be shaped as a
draft from TMDb is shaped, and each container the shaping makes beneath it SHALL be a new stop; one
the shaping ungroups, or unticks, SHALL leave the walk, and the specials placed in it SHALL be
unassigned again; one ticked again SHALL be a new stop once the stop above it is confirmed again.
Specials SHALL be placeable in a new stop as in a held one, and a new stop SHALL show the specials
placed in it as a held stop does, each with how it was placed and a way to unassign it. A new stop
SHALL be made only once it is confirmed: storing the walk SHALL name it in its parent before the first child listed after it there that
the parent names, or last when none is, and SHALL create it through the create route,
with the containers beneath it in one creation, right after the edit of its parent that names it, since
the create route makes a container beneath a parent only once the parent names it. Unchoosing a missing
child and confirming its parent's stop again SHALL remove its new stop and every stop beneath it from
the walk, after the console says which, and the specials placed in them SHALL be unassigned again.

#### Scenario: a season TMDb has that the library lacks
- **WHEN** a missing season is chosen at a held series' stop, and the stop is confirmed
- **THEN** the season is a new stop beneath the series, titled as TMDb titles it, with TMDb's year and
  references chosen

#### Scenario: a stop confirmed twice at once
- **WHEN** a missing season is chosen at a held series' stop, and the stop is confirmed twice before
  either confirm has finished
- **THEN** the season is one new stop beneath the series

#### Scenario: a special placed in a new season
- **WHEN** a special is placed as an entry of a new season, and the walk is stored
- **THEN** the season is created holding the entry, after the series' edit that names the season

#### Scenario: a special placed as an extra of a new serial
- **WHEN** a special is placed as an extra of a serial a new season's episodes were grouped into, while
  the serial's stop is open
- **THEN** the serial's stop shows the special among those placed there, as an extra of the serial, and
  unassigning it there returns it to the unassigned specials

#### Scenario: a new season regrouped
- **WHEN** a new season's episodes are regrouped into two serials
- **THEN** each serial is a new stop beneath the season

#### Scenario: a new season's serial ungrouped
- **WHEN** a serial a new season's episodes were grouped into, with a special placed in it, is
  ungrouped
- **THEN** the serial's stop leaves the walk, and the special is unassigned again

#### Scenario: a new season's serial unticked
- **WHEN** a serial a new season's episodes were grouped into, with a special placed in it, is
  unticked, and later ticked again and the season confirmed again
- **THEN** the serial's stop leaves the walk and the special is unassigned again, and once ticked again
  the serial is a stop beneath the season once more

#### Scenario: a new season unchosen
- **WHEN** a missing season chosen earlier is unchosen, and the series' stop is confirmed again
- **THEN** the season's stop and its serials' stops leave the walk, and a special placed in one of them
  is unassigned again

#### Scenario: a season TMDb puts between two the library holds
- **WHEN** a held series holds TMDb's first and third seasons, the second is chosen, its stop and the
  series' are confirmed, and the walk is stored
- **THEN** the second season is queued between the two, and the series' edit names it between them

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aMissingSeasonChosenInAWalkIsANewStop`,
`aStopConfirmedTwiceAtOnceDraftsItsSeasonsOnce`, `aSpecialPlacedInANewSeasonIsCreatedWithIt`,
`aNewSeasonsSerialsAreStopsBeneathIt`, `aGroupUngroupedInANewStopLeavesTheWalk`,
`aGroupLeftOutOfANewStopLeavesTheWalkUntilTickedAgain`,
`unchoosingAMissingSeasonRemovesItsStops`, `aStopsChildrenAreInTheOrderItsChildrenListThem`). The walk's sheet is
pinned by nothing yet, as the rest of the shell is.
