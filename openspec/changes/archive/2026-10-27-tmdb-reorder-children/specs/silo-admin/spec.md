<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A container is drafted from TMDb's record, and shaped before it is created
SiloAdmin SHALL search TMDb's movies and series by title. A container's `tmdb` reference SHALL be
read by its type: on a `movie` a movie's id, on a `collection` a collection's, on a `series` a
series', and on a `season` a season's. An entry's `tmdb` references SHALL be read only against a
reading, as the ids of the reading's episodes they match, since one entry may carry ids from more
than one of TMDb's ranges. Picking a record whose reference the
clone holds on a container of the same kind SHALL offer that container's import from smddb, and
SHALL NOT draft it. Picking one whose reference a container of the library carries SHALL NOT draft
it, and the console SHALL say the library holds it. Otherwise the console SHALL read the record as
containers: a movie as a `movie`; a series as a `series` with a `season` child for each of TMDb's
seasons but season 0, whose episodes are the series' specials; a season as a `season` holding each of its episodes as an entry, in TMDb's order; a
collection as a `collection` with each of its movies as a child; and, when the operator chooses one
of a series' episode groups as its shape, each group as a child container of the type the operator
picks, holding the group's episodes as entries in the group's order. Each container SHALL carry the
record's title, its year where its type has one, a `tmdb` reference, and a reference for each other
provider's id TMDb holds for it. Each episode's entry SHALL carry its references and no title or
outline, until the operator titles it. A container's outline SHALL be TMDb's overview, attributed to `tmdb` with the record's id.

Each container SHALL be a draft of a new container with an id from the clone's `provisionalID()`,
kept on this Mac as a new container's draft is. The top SHALL be filed beneath the container of the
library that carries the reference of the record above it, when there is one, or at the top of the
library. The form SHALL show each episode's title from TMDb beside its entry, marked as TMDb's, and
SHALL store none. The operator SHALL be able to shape the tree before it is created: re-type a
container, rename its primary sequence with the alternatives and placed specials naming it, and, when the
operator says, the primary sequence of each container beneath it, group entries into child containers, and drop what they will not hold. Each entry, and each
group as one, SHALL be ticked to be made, all of them ticked to begin with; one unticked SHALL be left
out when the tree is made, a group with everything in it, and an entry naming a container the library
holds already SHALL be shown ticked and SHALL NOT be choosable. The container's heading SHALL say how
many of its entries are ticked, and tick them all or none. A tick SHALL only say whether a child is made or taken: grouping SHALL work on
the entries the operator selects, each selected alone, a range of them, or one more at a time, and
no group SHALL be selected, so that a group is made of entries alone. The grouping SHALL be offered
both above the entries and on a right-click of the selection, or of the entry clicked when it is not
selected. Once a group is made, nothing
SHALL be selected. The heading and the grouping's actions SHALL stay in sight above the entries while
the entries scroll, and choosing a new group's kind SHALL leave its title ready to be typed. Entries SHALL be
selected, and those selected made a new group, of the kind, title and label the operator gives, its
primary sequence going by the id of the container's it is made out of, at the first one's place, ticked, or added to a group the draft holds beneath the same container, the group's entries
then in the container's order. A group SHALL be ticked whole; its entries SHALL be shown in it, none
choosable, each only to be taken out of it, back beside the group; and the group SHALL be able to be
ungrouped, its entries back in its place and the specials placed in it unassigned again. A group left
with nothing SHALL be ungrouped. Each of the container's entries, an episode or the entry naming a group,
SHALL be movable before another entry of its sequence, or last, by dragging its grab handle onto the entry it is to
go before or past the last, or from its right-click menu, a place up or down or to either end. A group's handle SHALL run beside all
its entries, and while the pointer is on a handle what it moves SHALL be shaded. A
special placed in the sequence SHALL keep after the entry it followed, and one placed first SHALL stay
first. A run of two or more entries in one sequence whose episodes TMDb
titles as the parts of one story, as `Terror of the Zygons (1)` to `(4)` are, SHALL be bracketed and
suggested as a group titled by the story, to be grouped one at a time or all at once. A part numbered
one after the part before it SHALL be one of that story's parts though TMDb titles its story otherwise,
as `Invasion (1)` is followed by `Invasion of the Dinosaurs (2)`, and the run SHALL be titled by the
story most of its parts name, the later on a tie. No kind SHALL be
assumed for a group: the kind the container's groups mostly are SHALL be chosen to begin with, when
it has any, and otherwise the operator SHALL choose one before any group is made. A run that is the
parts of the story the container is titled as, or that is every entry the container holds, as a
group made of a story's parts holds them, SHALL NOT be suggested as a group: it SHALL be suggested
instead to be titled by its parts' numbers, as `Episode 1` and on or `Part 1` and on, as the operator
chooses, the choice worded by the first and last of those numbers, and once titled SHALL be suggested
as nothing. The
console SHALL show the dry run of the whole tree as they shape it. Creating SHALL store the parent's edit
naming the top, as creating a child does, and then make the tree, with its attributions, in one
request to the silo.

#### Scenario: a film neither smddb nor the library holds
- **WHEN** the operator picks from TMDb a film whose reference neither the clone nor the library holds
- **THEN** a draft of a movie opens with the film's title and year, a `tmdb` reference and the other
  providers' ids TMDb holds, and its outline attributed to TMDb

#### Scenario: a series smddb holds
- **WHEN** the operator picks from TMDb a series whose reference a series in the clone carries
- **THEN** the console offers that series' import from smddb, and drafts nothing

#### Scenario: a season drafted beneath its series
- **WHEN** the operator picks from TMDb a season of a series the library holds by its reference, and
  creates it
- **THEN** the series' sidecar names the season, and the library holds the season with an entry for
  each episode carrying its references and no title, and no presentations

#### Scenario: a season's serials suggested from TMDb's titles
- **WHEN** a drafted season's episodes are titled at TMDb as three parts of one story, two of another,
  and one with no part number
- **THEN** the first three are suggested as a group titled by the first story, the next two as one
  titled by the second, and the last as none

#### Scenario: a serial's own parts
- **WHEN** a drafted season's three parts of one story are grouped as a serial titled by the story,
  and the serial is opened
- **THEN** its parts are not suggested as a group, and are suggested to be titled by their numbers;
  titled as parts, they are `Part 1` to `Part 3`, and are suggested as nothing

#### Scenario: a story's first part titled otherwise
- **WHEN** a drafted season's first episode is titled at TMDb as the first part of one story, and the
  next five as its second to sixth parts under a longer title
- **THEN** all six are suggested as one group titled by the longer title; grouped as a serial and
  titled as parts, they are `Part 1` to `Part 6`

#### Scenario: entries moved
- **WHEN** a drafted season's last episode is moved before the group its first episodes were made, and
  the group is then moved last, with one special placed after the group and one placed first
- **THEN** the season holds the episode first and the group last, the special placed after the group
  still follows it, and the one placed first is still first

#### Scenario: a group added to and taken from
- **WHEN** an entry before a group is added to it, and its last entry is then taken out of it
- **THEN** the group holds its entries in the season's order at the first one's place, and the entry
  taken out follows the group

#### Scenario: an entry and a group unticked
- **WHEN** one of a drafted season's entries and a group of three others are unticked, and the tree is
  made
- **THEN** the season is made without the entry, and neither the group nor its three entries are made

#### Scenario: groups made one after another
- **WHEN** the operator selects three entries, makes them a group, and selects the next two
- **THEN** nothing is selected once the group is made, and only the two are selected for the next
  group; the group is never among them

#### Scenario: a group ungrouped
- **WHEN** a group a special is placed in is ungrouped
- **THEN** its entries are back in its place, and the special is unassigned again

#### Scenario: a season regrouped into serials
- **WHEN** the operator regroups a drafted season's episodes into two serials beneath it, and creates it
- **THEN** the library holds the season, with the two serials beneath it, each holding its episodes in
  TMDb's order

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aContainerIsDraftedFromTMDb`,
`aRecordSmddbHoldsIsImportedRatherThanDrafted`, `serialsAreSuggestedFromTMDbsTitlesForTheirParts`,
`aDraftsGroupIsAddedToTakenFromAndUngrouped`, `aDraftsEntryUntickedIsLeftOutOfWhatIsMade`,
`aGroupsOwnPartsAreSuggestedToBeTitledByNumberRatherThanGroupedAgain`,
`aPartTitledOtherwiseButNumberedOnIsOneOfItsStorysParts`,
`aDraftsEntriesAndGroupsAreMovedWithTheSpecialsAfterThem`). The search, the shaping's sheet and the dry run as the
operator shapes are pinned by nothing yet, as the rest of the shell is.

### Requirement: A missing child chosen in a walk is a new container, created when the walk is stored
A missing child chosen at a stop of a walk SHALL join the walk, when the stop is confirmed, as a new
stop beneath it: a draft from TMDb, read as a draft from TMDb reads it, with ids from smddb's client.
It SHALL be drafted once, however many times the stop is confirmed, and the console SHALL take no
second confirm of a stop while one is under way. The walk's tree SHALL show it as new. Its fields and
references, and any artwork TMDb offers for it, SHALL be chosen to begin with. It SHALL be shaped as a
draft from TMDb is shaped, its entries moved as a draft's are, each special the walk places among them
keeping after the entry it followed, and each container the shaping makes beneath it SHALL be a new stop; one
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

#### Scenario: a new stop's entry moved
- **WHEN** a new season's first episode is moved last, with a special placed after it, and the walk is
  stored
- **THEN** the season is made with the episode last and the special after it

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
`unchoosingAMissingSeasonRemovesItsStops`, `aStopsChildrenAreInTheOrderItsChildrenListThem`,
`aNewStopsEntryMovedIsStoredWhereItWasMovedWithWhatFollowedIt`). The walk's sheet is pinned by nothing
yet, as the rest of the shell is, but for what a moved child reads from a drop:
`Tests/SiloAdminTests/GroupingSuggestionTests.swift` (`aChildDraggedIsReadBackFromItsText`).
