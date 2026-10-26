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
with nothing SHALL be ungrouped. A run of two or more entries in one sequence whose episodes TMDb
titles as the parts of one story, as `Terror of the Zygons (1)` to `(4)` are, SHALL be bracketed and
suggested as a group titled by the story, to be grouped one at a time or all at once. No kind SHALL be
assumed for a group: the kind the container's groups mostly are SHALL be chosen to begin with, when
it has any, and otherwise the operator SHALL choose one before any group is made. A run that is the
parts of the story the container is titled as, or that is every entry the container holds, as a
group made of a story's parts holds them, SHALL NOT be suggested as a group: it SHALL be suggested
instead to be titled by its parts' numbers, as `Episode 1` and on or `Part 1` and on, as the operator
chooses, and once titled SHALL be suggested as nothing. The
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
`aGroupsOwnPartsAreSuggestedToBeTitledByNumberRatherThanGroupedAgain`). The search, the shaping's sheet and the dry run as the
operator shapes are pinned by nothing yet, as the rest of the shell is.

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
dragging them, and a special SHALL be draggable onto the stop's extras by kind. The operator SHALL be able to rename a stop's primary
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
`aNewStopShowsTheAlternativesItsPlacedSpecialsMake`). The walk's sheet is pinned by nothing yet, as the rest
of the shell is, but for what its alternatives read from a drop: `Tests/SiloAdminTests/AlternativesEditorTests.swift`
(`aDragIsReadBackFromItsText`).
