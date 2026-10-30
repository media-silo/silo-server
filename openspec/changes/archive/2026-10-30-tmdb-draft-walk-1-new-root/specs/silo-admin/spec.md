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
kept on this Mac with the walk it roots. The top SHALL be filed beneath the container of the
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
go before or past the last, or from its right-click menu, a place up or down or to either end. One dropped where it already is, on
itself, on the entry after it or past the last when it is last, SHALL stay there, nothing moved. A group's handle SHALL run beside all
its entries, and while the pointer is on a handle what it moves SHALL be shaded. A
special placed in the sequence SHALL keep after the entry it followed, and one placed first SHALL stay
first. From the primary sequence's menu, a new container of the kind and title the operator gives
SHALL be added beneath the container, holding nothing yet, named last in its primary sequence, its own
primary sequence going by that one's id, and made with the draft; entries SHALL be added to it, and it
removed, as a group's are. A run of two or more entries in one sequence whose episodes TMDb
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
draft SHALL be shaped and made as the walk rooted at its top, which is how a record the library does
not hold is walked from a draft of it. A season picked of a series the library holds by its reference
SHALL NOT be drafted on its own: the series' walk SHALL open with the season chosen among its missing
children, drafted beneath the series once the series' stop is confirmed.

#### Scenario: a film neither smddb nor the library holds
- **WHEN** the operator picks from TMDb a film whose reference neither the clone nor the library holds
- **THEN** a draft of a movie opens with the film's title and year, a `tmdb` reference and the other
  providers' ids TMDb holds, and its outline attributed to TMDb

#### Scenario: a series smddb holds
- **WHEN** the operator picks from TMDb a series whose reference a series in the clone carries
- **THEN** the console offers that series' import from smddb, and drafts nothing

#### Scenario: a season drafted beneath its series
- **WHEN** the operator picks from TMDb a season of a series the library holds by its reference
- **THEN** the series' walk opens with the season chosen among its missing children; once the series'
  stop and the season's are confirmed and the walk is stored, the series' sidecar names the season,
  and the library holds the season with an entry for each episode carrying its references and no
  title, and no presentations

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

#### Scenario: an entry dropped where it is
- **WHEN** a drafted season's entry is dragged by its handle and dropped on itself, and then on the
  entry after it
- **THEN** the season's entries are in the order they were, and nothing is moved

#### Scenario: a container added
- **WHEN** a new serial is added to a drafted season, and one of the season's episodes is then added
  to it
- **THEN** the serial is named in the season, holding nothing until the episode is added, and is made
  with the draft holding the episode

#### Scenario: a group added to and taken from
- **WHEN** an entry before a group is added to it, and its last entry is then taken out of it
- **THEN** the group holds its entries in the season's order at the first one's place, and the entry
  taken out follows the group

#### Scenario: an entry and a group unticked
- **WHEN** one of a drafted season's entries and a group of three others are unticked, and the season
  is made
- **THEN** the season is made without the entry, and neither the group nor its three entries are made

#### Scenario: groups made one after another
- **WHEN** the operator selects three entries, makes them a group, and selects the next two
- **THEN** nothing is selected once the group is made, and only the two are selected for the next
  group; the group is never among them

#### Scenario: a group ungrouped
- **WHEN** a group a special is placed in is ungrouped
- **THEN** its entries are back in its place, and the special is unassigned again

#### Scenario: a season regrouped into serials
- **WHEN** the operator regroups a drafted season's episodes into two serials beneath it, and makes it
- **THEN** the library holds the season, with the two serials beneath it, each holding its episodes in
  TMDb's order

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aContainerIsDraftedFromTMDb`,
`aRecordSmddbHoldsIsImportedRatherThanDrafted`, `serialsAreSuggestedFromTMDbsTitlesForTheirParts`,
`aDraftsGroupIsAddedToTakenFromAndUngrouped`, `aDraftsEntryUntickedIsLeftOutOfWhatIsMade`,
`aGroupsOwnPartsAreSuggestedToBeTitledByNumberRatherThanGroupedAgain`,
`aPartTitledOtherwiseButNumberedOnIsOneOfItsStorysParts`,
`aDraftsEntriesAndGroupsAreMovedWithTheSpecialsAfterThem`,
`aContainerAddedToADraftIsAnEmptyGroupMadeWithIt`). The search, and the walk's sheet the draft is shaped in,
are pinned by nothing yet, as the rest of the shell is, but for where a child dropped where it is goes: `Tests/SiloAdminTests/GroupingSuggestionTests.swift` (`aChildDroppedWhereItIsStays`).

## ADDED Requirements

### Requirement: A record the library does not hold is walked from a draft of it
Picking a TMDb record that neither smddb's clone nor the library holds SHALL start a walk rooted at
the draft's top, shown in the same sheet as a walk of a held tree: the walk's tree, the open stop and,
for a series, its specials beside every stop. The root SHALL be a new stop with no stop above it in
the walk, opened, shaped and confirmed as any new stop is, its fields and references chosen to begin
with; confirming it SHALL add the containers of its draft beneath it as new stops. A drafted series
SHALL be the series whose specials sit beside every stop, each suggested where it goes as a draft's
specials are. Storing the walk SHALL make nothing of a root not confirmed. A confirmed root SHALL be
made, with the confirmed containers beneath it and their attributions, in one creation: at the top of
the library, after the walk's companion series and before any other step; or, for a film filed beneath
a collection the library holds, beneath that collection, once that collection's sidecar is edited to
name it. A drafted series SHALL then decline the specials declined in it. The walk SHALL be kept on
this Mac as a walk of a held tree is, and picking the same record for the same library again SHALL
offer to resume it or start again, starting again drafting the record afresh.

#### Scenario: a series the library lacks
- **WHEN** the operator picks a series neither the clone nor the library holds, declines its one
  special, and confirms the series' stop and the stop of its one season
- **THEN** storing the walk makes the series at the top of the library with the season beneath it,
  and the series declines the special

#### Scenario: a drafted root not confirmed
- **WHEN** a walk rooted at a draft of a series is stored before the series' stop is confirmed
- **THEN** storing makes nothing

#### Scenario: a film in a collection the library holds
- **WHEN** the operator picks a film the library lacks whose collection the library holds, and
  confirms the film's stop
- **THEN** storing the walk names the film in the collection first, then makes it beneath the
  collection

#### Scenario: a walk of a record resumed
- **WHEN** a walk rooted at a draft of a record is kept, and the same record is picked for the same
  library again
- **THEN** the console offers to resume that walk, or start again with a new draft of the record

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aRecordTheLibraryLacksIsWalkedFromADraft`).
The walk's sheet, the offer to resume, and starting again are pinned by nothing yet, as the rest of
the shell is.
