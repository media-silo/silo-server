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
of the episodes selected, its primary sequence going by the id of the held container's as the walk
leaves it, as a draft's entries are, ticked, or added to a group made there already; runs TMDb titles as the parts of one
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
A held stop's children SHALL be listed in one list, in its primary sequence's order as storing would
leave it were every child listed ticked: what it holds already and each special placed in it, those
storing adds marked, among its missing episodes, its groups and the containers held beneath it, an
unticked child in its place to be ticked there, and a group whose own stop is not yet drafted after
the child it follows. Each SHALL be movable before another, or last, by its grab handle or from its
right-click menu, as a draft's entries are. The order SHALL be kept
with the walk, the stop pending again, and SHALL give the stop's edit its primary sequence; an entry the
order does not name, as a special placed after the order was given, SHALL keep its place. The moves SHALL
be undoable at once, the entries then listed as they would have been.
Chosen artwork SHALL be put with its attribution when the walk is stored. The
console SHALL read a container against TMDb only when its stop is opened, or as the next stop to be
opened.

#### Scenario: a held stop's entries moved
- **WHEN** a held serial's first part is moved last at its stop, with a special placed in it before
  the move and another placed first after it, and the walk is stored
- **THEN** the serial's primary sequence holds the special placed after the move first, then the
  other special, the rest of its parts, and the first part last

#### Scenario: a held stop's children listed in order
- **WHEN** a held season holds a serial and lacks four episodes, one of them unticked, and the parts of
  the next story grouped, and the group is moved before the serial
- **THEN** its children list the group, the serial, then the four episodes, the unticked one in its
  place; once the season and the group are confirmed, storing names the group first

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
(`aHeldContainersDifferencesFromTMDbAreTakenOrLeft`, `aHeldStopsEntriesMovedAreStoredInTheirNewOrder`,
`aHeldStopsChildrenAreListedInTheOrderStoringLeavesThem`,
`aHeldSeasonsMissingEpisodesGroupedAreMadeAContainerBeneathIt`,
`aHeldSeasonsMissingEpisodesAreAddedToAContainerHeldBeneathIt`,
`aHeldSeasonsGroupsAreNewStopsBeneathItOnceConfirmed`). The list and its choosing are pinned by nothing
yet, as the rest of the shell is.
