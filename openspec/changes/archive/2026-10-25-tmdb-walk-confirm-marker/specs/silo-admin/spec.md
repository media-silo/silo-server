<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A held container's differences from TMDb are listed, and the operator takes each or leaves it
For a container the library holds, SiloAdmin SHALL read TMDb's record of the container's `tmdb`
reference, as a draft from TMDb reads it. A container with no `tmdb` reference of its own SHALL be read
through the nearest container above it that has one, or, when none above it has one, through a
container of the library that refers to its items; its differences SHALL be about the entries it
holds. Picking from TMDb a record whose reference a container of the library carries SHALL open that
container's differences. A TMDb id SHALL count as covered when the container, a container beneath it,
or an item the container refers to carries it, or when the container's sidecar declines it. The
console SHALL list how the library's sidecar differs from the reading:

- a title, year or outline that differs, the outline shown with its attribution;
- each provider's id TMDb holds that the sidecar lacks, for the container and for each entry it holds;
- each of TMDb's episodes or seasons, other than a special, whose id is not covered, with where TMDb
  puts it;
- items that both hold, at the same level, in a different order;
- each artwork kind the container's folder has no file for and TMDb has an image for;
- for a series, each special whose id is not covered, as unassigned, to be placed or declined as a
  draft's specials are, with its suggestion;
- for a series, collapsed, each special its sidecar declines, which the operator may place after all,
  removing the decline.

An item, child or extra the library holds and TMDb does not SHALL be shown, and SHALL NOT be offered
for removal. Each difference SHALL be chosen or not, none chosen to begin with, and one not chosen
SHALL change nothing. Each group's differences SHALL be chosen all at once or none, the group showing
when only some of them are chosen. Confirming the container's stop in a walk SHALL keep its chosen
field, reference, entry and order differences as one pending edit of the container, based on the
sidecar its stop read, carrying the outline's attribution when the outline is chosen, and the declined
refs when a special is declined or placed after all, and stored when the walk is stored. A special
placed in a duplicate's home or a breakout SHALL be an edit of that container too, and the console
SHALL list every edit before it stores any. A chosen child container SHALL join the walk as a new stop
beneath the container. The episodes a held container lacks SHALL be groupable into new containers
beneath it as a draft's entries are, a group of the kind, title and label the operator gives, made
of the episodes selected, as a draft's entries are, ticked, or added to a group made there already; runs TMDb titles as the parts of one
story SHALL be suggested as a draft's are, but for a run of the story the held container is titled
as, which is its own parts, and SHALL instead be offered to be titled by its part numbers, as a
draft's own parts are, the entries the walk adds for them carrying those titles. A group SHALL be chosen whole, its episodes shown in it,
each only to be taken out of it or the group ungrouped, each episode then chosen as the group was. A
group chosen SHALL be made, when the walk is stored, as a container beneath the held one holding its
episodes in TMDb's order, named in the held container's edit where the first of them would have gone,
and none of its episodes SHALL be added to the held container itself. Confirming the held
container's stop SHALL add each group it takes to the walk as a new stop beneath it, holding its
episodes, where specials SHALL be placeable and its parts shaped as in a new stop drafted from TMDb;
storing the walk SHALL make it from that stop, with what was placed and shaped there, only once that
stop is confirmed, as every new container is, and not otherwise. A group whose episodes change SHALL be a new stop again,
the specials placed in it unassigned, once the held container's stop is confirmed again, and one
ungrouped or unchosen SHALL leave the walk then. Each container the held one
holds beneath it SHALL be shown among its children, at the place of the first of TMDb's episodes it
holds, or after them when it holds none, and its missing episodes selected SHALL be addable to it as
to a group made there, each only to be taken out of it again, chosen then, or grouped instead. One
put there SHALL be one of that container's own missing episodes from then on, chosen at its stop to
begin with, and grouped and taken there as any of its own are; none of them SHALL be added to the held
container itself, and an entry TMDb puts after one of them SHALL follow the container.
Chosen artwork SHALL be put with its attribution when the walk is stored. The
console SHALL read a container against TMDb only when its stop is opened, or as the next stop to be
opened.

#### Scenario: an episode TMDb has gained
- **WHEN** a season the library holds lacks an episode TMDb's record of the season has, and the
  operator chooses that difference alone, confirms the season's stop and stores the walk
- **THEN** the season's edit adds one entry carrying the episode's references at TMDb's position, and
  changes nothing else

#### Scenario: missing episodes grouped
- **WHEN** a held season lacks four parts of one story and the first part of the next, the four are
  grouped as a serial, all five are chosen, the season's stop and then the serial's are confirmed, and
  the walk is stored
- **THEN** the serial is created beneath the season holding the four, the season's edit names it where
  the first part would have gone, and the next story's part follows it

#### Scenario: a group of missing episodes as a new stop
- **WHEN** a held season's missing parts of one story are grouped as a serial and chosen, the season's
  stop is confirmed, a special is placed as an extra of the serial at its stop, that stop is confirmed,
  and the walk is stored
- **THEN** the serial is a new stop beneath the season, created holding the parts with the special as
  its extra, and the season's edit names it where the first part would have gone

#### Scenario: missing parts added to a serial held beneath
- **WHEN** a held season holds a serial beneath it holding the first story's parts, lacks two parts of
  the next story, which are added to that serial, chooses the third part, confirms the serial's
  stop with both of the two chosen there, and the walk is stored
- **THEN** the serial is shown among the season's children before the missing parts, the serial gains
  the two parts after its own, and the season's edit adds the third part after the serial and neither
  of the two

#### Scenario: an extra TMDb does not know
- **WHEN** a container the library holds has an extra that TMDb's record has nothing for
- **THEN** the extra is shown, and nothing offers to remove it

#### Scenario: a serial with no reference of its own
- **WHEN** a serial with no TMDb reference, beneath a season that has one, holds an episode whose
  IMDb id TMDb holds and the serial's sidecar lacks
- **THEN** the serial's differences list that IMDb id against the episode's entry

#### Scenario: episodes regrouped into serials
- **WHEN** a season holds every one of TMDb's episodes for it within serials beneath it
- **THEN** no episode is listed as missing, and no order difference is listed

#### Scenario: specials placed elsewhere or declined
- **WHEN** a series refers to one special's home in another library and to another special's entry in
  a breakout, and its sidecar declines a third
- **THEN** none of the three is listed as unassigned, and the third is listed among the declined

#### Scenario: a special TMDb has gained
- **WHEN** TMDb's season 0 for a series the library holds has gained a special nothing covers
- **THEN** the special is listed as unassigned, with a suggestion, and not as a missing episode

#### Scenario: a breakout read through the series that refers to it
- **WHEN** a breakout with no TMDb reference holds entries a series refers to, and TMDb holds an IMDb
  id for one of those specials that the breakout's entry lacks
- **THEN** the breakout's differences list that IMDb id against the entry

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aHeldContainersDifferencesFromTMDbAreTakenOrLeft`,
`aHeldSeasonsMissingEpisodesGroupedAreMadeAContainerBeneathIt`,
`aHeldSeasonsMissingEpisodesAreAddedToAContainerHeldBeneathIt`,
`aHeldSeasonsGroupsAreNewStopsBeneathItOnceConfirmed`). The list and its choosing are pinned by nothing
yet, as the rest of the shell is.

### Requirement: A held container's tree is reviewed against TMDb as a walk, a container at a time
Opening a held container's differences SHALL start a walk rooted at it, whose first stop is the
container. Confirming a stop SHALL be the operator saying it is as it should be, so that the walk need not come
back to it before it is stored: it SHALL keep its chosen differences as the container's pending change, and
SHALL add as pending stops beneath it each container the library holds beneath it, and each new one,
in the order its children list them, whatever their ids: a series' seasons in TMDb's order, a held
container's other children each at its place among its missing episodes, and a new container's in
its draft's order; a stop never read SHALL add them in the order its sequences hold them. A stop confirmed with nothing chosen and nothing placed in it SHALL be confirmed and unchanged. Pending stops
SHALL be opened in the tree's order, depth first. The console SHALL show the walk's tree as far as the
walk has found it, each stop with its state, which SHALL say what storing the walk would do: pending, not confirmed; or
confirmed, and then that storing creates its container, creates it only once a stop above it named
there is confirmed, edits it, or leaves it unchanged, as the store would find it. The operator SHALL
be able to open any stop of the walk, and a confirmed stop SHALL open with its choices and placements
as they were left. Any change to a confirmed stop's choices, a difference ticked or unticked, its
missing episodes grouped, ungrouped, titled or put into a container held beneath it, a special placed
in it or taken from it, or its draft shaped, SHALL make it pending again with its choices kept, and so
SHALL unconfirming it; a change to the missing episodes put into a held container SHALL make that
container's stop pending too. Confirming a stop again SHALL replace its pending change. When the walk's root is a
series, or is beneath one, the series' unassigned specials SHALL be shown beside every stop with their
suggestions. A special suggested for the open stop SHALL be marked as suggested there only on
something that ties it there: its title naming the stop, an entry of it, the story TMDb titles an
entry a part of, or a container beneath it; or smddb filing it there. A series' own title, which any
of its specials may carry, SHALL tie nothing. A special SHALL be
placeable in the open stop, as an entry in a sequence of it at a position or as one of its extras, and
anywhere a draft's specials may be placed. A placed special SHALL leave the unassigned specials and
become part of the pending change of the container it was placed in, and removing it from that change
SHALL return it. A stop never opened or left pending, and a special never placed, SHALL change nothing.

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

#### Scenario: a ticked difference ticked again
- **WHEN** a difference a confirmed stop has ticked is ticked again
- **THEN** the stop stays confirmed

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`confirmingAStopQueuesTheContainersBeneathItInTheTreesOrder`,
`aStopsChildrenAreInTheOrderItsChildrenListThem`, `anyChangeToAConfirmedStopMakesItPendingAgain`,
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
SHALL be made only once it, and every new stop above it, is confirmed; one beneath a pending new stop
SHALL be said to be waiting on it, and one not confirmed SHALL be left out of what is made above it.
Once made, storing the walk SHALL name it in its parent before the first child listed after it there that
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

#### Scenario: a new season's serial not confirmed
- **WHEN** a new season's episodes are regrouped into two serials, the season and one serial are
  confirmed, and the walk is stored
- **THEN** the season is made with the confirmed serial and without the other

#### Scenario: a new season not confirmed
- **WHEN** a new season's serial is confirmed and the season is not
- **THEN** the serial's stop says it is created once the season is confirmed

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aMissingSeasonChosenInAWalkIsANewStop`,
`aStopConfirmedTwiceAtOnceDraftsItsSeasonsOnce`, `aSpecialPlacedInANewSeasonIsCreatedWithIt`,
`aNewSeasonsSerialsAreStopsBeneathIt`, `aGroupUngroupedInANewStopLeavesTheWalk`,
`aGroupLeftOutOfANewStopLeavesTheWalkUntilTickedAgain`,
`unchoosingAMissingSeasonRemovesItsStops`, `aStopsChildrenAreInTheOrderItsChildrenListThem`). The walk's sheet is
pinned by nothing yet, as the rest of the shell is.
