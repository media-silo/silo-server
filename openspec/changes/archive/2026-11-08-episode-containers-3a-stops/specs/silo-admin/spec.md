<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A walk drafts each episode as a container, a stop of its own
Wikidata's reading of a season or a serial SHALL draft each episode it holds as a container of type
`episode` beneath it, in Wikidata's order, holding one sequence `main` of one leaf `feature` of type
`episode`. The episode's container SHALL carry its label as its title, its publication date as its
`premiered`, its cast members as its cast, each with the character they play, its directors and then
its screenwriters as its crew, with the roles `Director` and `Writer`, a `wikidata` reference and
each provider's id Wikidata holds for it, and for each participant a `wikidata` reference and the
other ids Wikidata holds for them. Its outline SHALL be TMDb's overview of the episode in the TMDb
season it is read through, matched by the TMDb episode id Wikidata holds, and attributed to `tmdb`
with that id and the day it was read; a reading SHALL go on without it when TMDb does not answer, the
episode has no TMDb id, or TMDb gives it no overview. Each episode SHALL be a stop of the walk, queued
when its parent is confirmed as every child is. A new episode's stop SHALL offer its outline, first
date, cast, crew and references, each chosen to begin with, and the episode SHALL be made with its
title whatever is left out. A missing episode chosen at a held stop SHALL be drafted so, its outline
read with the stop, titled with the operator's own title for it when it has one, and SHALL join the
walk as a new stop beneath the stop once the stop is confirmed; storing the walk SHALL name it in the
held container's edit after the episode Wikidata puts it after, once its own stop is confirmed, and
make it right after that edit. An episode container the library holds beneath a season or a serial
SHALL be matched by the ids it carries: neither missing nor out of order there, and offered its
references at its own stop. A held episode SHALL be read against Wikidata's item of its `wikidata`
reference, or, carrying none, as the episode of what it is beneath that carries another id it carries,
and then offered Wikidata's id. Its differences SHALL list each of its title, outline, first date, cast,
and directors and writers that its provider has a value for and its container lacks or holds
differently; crew of another job SHALL NOT be offered for removal. Storing the walk SHALL edit a held
episode with each field chosen replaced by its provider's, its directors and writers replaced and the
rest of its crew kept after them, and the rest as the library held them; an outline chosen SHALL be
attributed to the episode's TMDb id with the day it was read. With no TMDb token, every fact SHALL
still be offered. Renaming the primary sequences beneath a stop SHALL leave an episode's own sequence
as it is.

#### Scenario: a season's episodes drafted as containers
- **WHEN** a season Wikidata holds with three episodes is drafted, TMDb's season giving an overview of
  the first alone
- **THEN** the draft holds the season with three episode containers beneath it in Wikidata's order,
  each holding its feature and carrying its title, first date and references, and only the first an
  outline, TMDb's, attributed to the episode's TMDb id

#### Scenario: an episode's crew
- **WHEN** an episode Wikidata lists one director and one screenwriter for is drafted
- **THEN** its crew holds the director and then the screenwriter, with the roles `Director` and
  `Writer`, each carrying their Wikidata id

#### Scenario: a new episode with its fields left out
- **WHEN** a new episode's stop is confirmed with its outline, first date and cast unticked, and the
  walk is stored
- **THEN** the episode is made with its title and crew, and no outline, first date or cast

#### Scenario: a held episode's fields
- **WHEN** a held episode titled otherwise, with no first date and a producer in its crew, is walked,
  and every difference but its cast is taken
- **THEN** storing the walk gives it Wikidata's title and first date, Wikidata's directors and writers
  with the producer after them, and TMDb's outline attributed to the episode's TMDb id, and no cast

#### Scenario: a held episode carrying no Wikidata id
- **WHEN** a held episode carries only the TMDb id Wikidata holds for one of its season's episodes
- **THEN** it is read as that episode, and offered its Wikidata id

#### Scenario: a held season's episodes as stops
- **WHEN** a held season names episode containers for the first and third of Wikidata's episodes,
  lacks the second, which is chosen, and the season's stop and the second's are confirmed and the walk
  stored
- **THEN** nothing of the two is listed at the season, both are stops beneath it with the new one
  between them, and the season names the second's container between them, made with TMDb's outline
  of it

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aSeasonsEpisodesAreDraftedAsContainers`,
`aHeldEpisodeIsOfferedEachFieldItsProviderHas`, `aHeldSeasonsEpisodesAreStopsBeneathIt`,
`aStopsPrimarySequenceIsRenamedBeneathItAndGivenToItsGroups`);
`Tests/SiloAdminKitTests/WikidataClientTests.swift` (`aSeasonIsReadAsItsEpisodesInOrder`).

## MODIFIED Requirements

### Requirement: A container is drafted from Wikidata's item, and shaped before it is created
SiloAdmin SHALL search Wikidata's films, series and collections by title, the most widely known
first, each shown with Wikidata's description of it and its kind. Picking an item whose `wikidata`
reference the clone holds on a container of the same kind SHALL offer that container's import from
smddb, and SHALL NOT draft it. Picking one whose reference a container of the library carries SHALL
NOT draft it, and the console SHALL say the library holds it. Otherwise the console SHALL read the
item as containers, as Wikidata's statements say them: a film as a `movie`; a series as a `series`
with a `season` child for each of Wikidata's seasons of it, or for each of those the operator
chooses; a season as a `season` holding, in Wikidata's order, each of its episodes as an `episode`
container beneath it and each of its serials as a `serial` beneath it, holding the serial's parts as
`episode` containers in Wikidata's order, as a walk drafts each episode; and a collection as a `collection` with each of its films as a child. Each container SHALL
carry its item's label as its title, its year where its type has one, a `wikidata` reference, and a
reference for each other provider's id Wikidata holds for it. The entry naming an episode's container
SHALL carry no references of its own: they are the container's. A container's outline SHALL
be the overview of the TMDb record named by the TMDb id Wikidata holds for its item, attributed to
`tmdb` with that id: a film's, a collection's or a series' own, and a season's beneath the series
above it, read by the number TMDb's series gives the season of that id. A container whose item
holds no TMDb id, or whose record TMDb does not answer for, SHALL be drafted with no outline. TMDb's
season 0 SHALL NOT be read: a series' specials are those Wikidata files beneath it.

Each container SHALL be a draft of a new container with an id from the clone's `provisionalID()`,
kept on this Mac with the walk it roots. The top SHALL be filed beneath the container of the
library that carries the reference of the record above it, when there is one, or at the top of the
library. The form SHALL show each episode by its container's title. The operator SHALL be able to shape the tree before it is created: re-type a
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
removed, as a group's are. A run of two or more entries in one sequence whose episodes Wikidata
titles as the parts of one story, as `Terror of the Zygons (1)` to `(4)` are, SHALL be bracketed and
suggested as a group titled by the story, to be grouped one at a time or all at once. A part numbered
one after the part before it SHALL be one of that story's parts though Wikidata titles its story otherwise,
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
not hold is walked from a draft of it. A season chosen from Wikidata's seasons of a series the library
holds by its reference SHALL NOT be drafted on its own: the series' walk SHALL open with the season chosen among its missing
children, drafted beneath the series once the series' stop is confirmed.

#### Scenario: a film neither smddb nor the library holds
- **WHEN** the operator picks from Wikidata a film whose reference neither the clone nor the library
  holds, and whose item holds a TMDb id
- **THEN** a draft of a movie opens with the film's title and year, a `wikidata` reference and the
  other providers' ids Wikidata holds, and TMDb's overview as its outline, attributed to TMDb

#### Scenario: a series smddb holds
- **WHEN** the operator picks from Wikidata a series whose reference a series in the clone carries
- **THEN** the console offers that series' import from smddb, and drafts nothing

#### Scenario: a season drafted beneath its series
- **WHEN** the operator chooses one of Wikidata's seasons of a series the library holds by its
  reference
- **THEN** the series' walk opens with the season chosen among its missing children; once the series'
  stop, the season's and its episodes' are confirmed and the walk is stored, the series' sidecar
  names the season, and the library holds the season naming a container for each episode, carrying
  its title and references, and no presentations

#### Scenario: a season's serials suggested from Wikidata's titles
- **WHEN** a drafted season's episodes are titled at Wikidata as three parts of one story, two of another,
  and one with no part number
- **THEN** the first three are suggested as a group titled by the first story, the next two as one
  titled by the second, and the last as none

#### Scenario: a serial's own parts
- **WHEN** a drafted season's three parts of one story are grouped as a serial titled by the story,
  and the serial is opened
- **THEN** its parts are not suggested as a group, and are suggested to be titled by their numbers;
  titled as parts, they are `Part 1` to `Part 3`, and are suggested as nothing

#### Scenario: a story's first part titled otherwise
- **WHEN** a drafted season's first episode is titled at Wikidata as the first part of one story, and the
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
  Wikidata's order

#### Scenario: a season Wikidata holds as serials
- **WHEN** a season is drafted whose item Wikidata lists two serials of, each with its parts
- **THEN** the draft of the season holds a serial beneath it for each, in Wikidata's order, each
  holding its parts as entries in Wikidata's order

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aContainerIsDraftedFromWikidata`,
`aRecordSmddbHoldsIsImportedRatherThanDrafted`, `serialsAreSuggestedFromWikidatasTitlesForTheirParts`,
`aSeasonOfSerialsIsDraftedAsItsSerials`,
`aDraftsGroupIsAddedToTakenFromAndUngrouped`, `aDraftsEntryUntickedIsLeftOutOfWhatIsMade`,
`aGroupsOwnPartsAreSuggestedToBeTitledByNumberRatherThanGroupedAgain`,
`aPartTitledOtherwiseButNumberedOnIsOneOfItsStorysParts`,
`aDraftsEntriesAndGroupsAreMovedWithTheSpecialsAfterThem`,
`aContainerAddedToADraftIsAnEmptyGroupMadeWithIt`). The search, and the walk's sheet the draft is shaped in,
are pinned by nothing yet, as the rest of the shell is, but for where a child dropped where it is goes: `Tests/SiloAdminTests/GroupingSuggestionTests.swift` (`aChildDroppedWhereItIsStays`).

### Requirement: A held container's differences from Wikidata and TMDb are listed, and the operator takes each or leaves it
For a container the library holds, SiloAdmin SHALL read Wikidata's item of the container's
`wikidata` reference for its facts, as a draft from Wikidata reads it, and TMDb's record of the TMDb
id Wikidata holds for the item, or failing one the container's own `tmdb` reference, for its content.
A container with no `wikidata` reference of its own SHALL be read through the nearest container above
it that has one, or, when none above it has one, through the Wikidata ids its entries carry, as a
breakout's are; its differences SHALL be about the entries it holds, and the reading SHALL say what it
was read through. A container none of which carries a Wikidata id SHALL be read through nothing, and
say why. Picking from Wikidata an item whose reference a container of the library carries SHALL open
that container's differences. An episode SHALL be matched to an entry carrying its Wikidata id or one
of the other ids Wikidata holds for it, or naming an episode container that carries one, and SHALL
count as covered when the container, a container beneath it, or an item the container refers to
carries one of them, or when the container's sidecar declines one. The console SHALL list how the library's sidecar differs from the reading:

- a title or year that differs from Wikidata's, and an outline that differs from TMDb's, the outline
  shown with its attribution;
- each provider's id Wikidata holds that the sidecar lacks, for the container and for each entry it
  holds, an episode container's at its own stop;
- each of Wikidata's episodes, seasons or serials, other than a special, that is not covered, with
  where Wikidata puts it, and each of its seasons or serials the container holds beneath it, shown
  among its children and never chosen;
- items that both hold, at the same level, in an order other than Wikidata's;
- each artwork kind the container's folder has no file for and TMDb has an image for;
- for a series, each special whose id is not covered, as unassigned, to be placed or declined as a
  draft's specials are, with its suggestion;
- for a series, collapsed, each special its sidecar declines, which the operator may place after all,
  removing the decline.

An item, child or extra the library holds and Wikidata does not SHALL be shown, and SHALL NOT be offered
for removal. Each difference SHALL be chosen or not, none chosen to begin with, and one not chosen
SHALL change nothing. Each group's differences SHALL be chosen all at once or none, the group showing
when only some of them are chosen. Confirming the container's stop in a walk SHALL keep its chosen
field, reference, entry and order differences as one pending edit of the container, based on the
sidecar its stop read, carrying the outline's attribution when the outline is chosen, and the declined
refs when a special is declined or placed after all, and stored when the walk is stored. A special
placed in a duplicate's home or a breakout SHALL be an edit of that container too, and the console
SHALL list every edit before it stores any. A chosen child container, or a chosen missing episode,
SHALL join the walk as a new stop beneath the container. The episodes a held container lacks SHALL be groupable into new containers
beneath it as a draft's entries are, a group of the kind, title and label the operator gives, made
of the episodes selected, its primary sequence going by the id of the held container's as the walk
leaves it, as a draft's entries are, ticked, or added to a group made there already; runs Wikidata titles as the parts of one
story SHALL be suggested as a draft's are, but for a run of the story the held container is titled
as, which is its own parts, and SHALL instead be offered to be titled by its part numbers, as a
draft's own parts are, the episode containers the walk drafts for them carrying those titles. A group SHALL be chosen whole, its episodes shown in it,
each only to be taken out of it or the group ungrouped, each episode then chosen as the group was. A
group chosen SHALL be made, when the walk is stored, as a container beneath the held one holding its
episodes as episode containers in Wikidata's order, named in the held container's edit where the first of them would have gone,
and none of its episodes SHALL be added to the held container itself. Confirming the held
container's stop SHALL add each group it takes to the walk as a new stop beneath it, holding its
episodes, where specials SHALL be placeable and its parts shaped as in a new stop drafted from Wikidata;
storing the walk SHALL make it from that stop, with what was placed and shaped there, only once that
stop is confirmed, as every new container is, and not otherwise. A group whose episodes change SHALL be a new stop again,
the specials placed in it unassigned, once the held container's stop is confirmed again, and one
ungrouped or unchosen SHALL leave the walk then. Each container the held one
holds beneath it SHALL be shown among its children, at the place of the first of Wikidata's episodes it
holds, or after them when it holds none, and its missing episodes selected SHALL be addable to it as
to a group made there, each only to be taken out of it again, chosen then, or grouped instead. One
put there SHALL be one of that container's own missing episodes from then on, chosen at its stop to
begin with, and grouped and taken there as any of its own are; none of them SHALL be added to the held
container itself, and an entry Wikidata puts after one of them SHALL follow the container.
A held stop's children SHALL be listed in one list, in its primary sequence's order as storing would
leave it were every child listed ticked: what it holds already and each special placed in it, those
storing adds marked, among a series' seasons, held or missing, its missing episodes, its groups and
the containers held beneath it, an unticked child in its place to be ticked there, and a missing season
or a group whose own stop is not yet drafted after the child it follows. Each SHALL be movable before another, or last, by its grab handle or from its
right-click menu, as a draft's entries are, and the walk SHALL take the stops beneath it in the order
they are moved into, as soon as they are moved; until then, a series' seasons in Wikidata's order. A
missing season, which no sequence names until it is made, SHALL be named in the series when it is made
before the first child it was moved before that the series names. The order SHALL be kept
with the walk, the stop pending again, and SHALL give the stop's edit its primary sequence; an entry the
order does not name, as a special placed after the order was given, SHALL keep its place. The moves SHALL
be undoable at once, the entries then listed as they would have been. From the primary sequence's menu,
a new container of the kind and title the operator gives SHALL be added beneath a held stop, holding
nothing yet, its primary sequence going by the held stop's id: a new stop of the walk, listed among the
held stop's children, last to begin with, ticked there and removable there at once, where specials
SHALL be placeable and its own children shaped as in any new stop. It SHALL be made beneath the held container when the walk is stored, once both are
confirmed, named in it where a new container is; unticked, it SHALL leave the walk once the held stop
is confirmed. Added beneath a new stop, it SHALL be a container of that stop's draft, as one added to a
draft is.
Chosen artwork SHALL be put with its attribution when the walk is stored. The
console SHALL read a container against Wikidata and TMDb only when its stop is opened, or as the next
stop to be opened.

#### Scenario: a container added beneath a held stop
- **WHEN** two containers are added beneath a held serial, one is unticked, the serial is confirmed,
  and the other's stop is confirmed and the walk stored
- **THEN** the unticked one has left the walk, and the other is made beneath the serial, named last in
  its primary sequence

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

#### Scenario: a series' seasons moved
- **WHEN** a held series holds three seasons and lacks a fourth, which is ticked, the fourth is moved
  first and the series' second held season last, and the series and the new season are confirmed and
  the walk stored
- **THEN** the series names the new season first and the moved held season last, and the walk took the
  stops beneath the series in that order once it was confirmed

#### Scenario: an episode Wikidata has gained
- **WHEN** a season the library holds lacks an episode Wikidata's item of the season has, and the
  operator chooses that difference alone, confirms the season's stop and stores the walk
- **THEN** the episode is a new stop beneath the season; once that stop is confirmed too, storing the
  walk names the episode's container in the season's edit at Wikidata's position, changing nothing
  else, and makes it beneath the season

#### Scenario: missing episodes grouped
- **WHEN** a held season lacks four parts of one story and the first part of the next, the four are
  grouped as a serial, all five are chosen, the season's stop and then the serial's are confirmed, and
  the walk is stored
- **THEN** the serial is created beneath the season holding the four as episode containers, the
  season's edit names it where the first part would have gone, and the next story's part, a container
  of its own, follows it

#### Scenario: a group of missing episodes as a new stop
- **WHEN** a held season's missing parts of one story are grouped as a serial and chosen, the season's
  stop is confirmed, a special is placed as an extra of the serial at its stop, that stop is confirmed,
  and the walk is stored
- **THEN** the serial is a new stop beneath the season, created holding the parts with the special as
  its extra, and the season's edit names it where the first part would have gone

#### Scenario: missing parts added to a serial held beneath
- **WHEN** a held season holds a serial beneath it holding the first story's parts, lacks two parts of
  the next story, which are added to that serial, chooses the third part, confirms the serial's
  stop with both of the two chosen there, and every new stop, and the walk is stored
- **THEN** the serial is shown among the season's children before the missing parts, the serial names
  the two parts' containers after its own, and the season's edit names the third part's after the
  serial and neither of the two

#### Scenario: an extra Wikidata does not know
- **WHEN** a container the library holds has an extra that Wikidata's item has nothing for
- **THEN** the extra is shown, and nothing offers to remove it

#### Scenario: a serial with no reference of its own
- **WHEN** a serial with no Wikidata reference, beneath a season that has one, holds an episode whose
  IMDb id Wikidata holds and the serial's sidecar lacks
- **THEN** the serial's differences list that IMDb id against the episode's entry

#### Scenario: episodes regrouped into serials
- **WHEN** a season holds every one of Wikidata's episodes for it within serials beneath it
- **THEN** no episode is listed as missing, and no order difference is listed

#### Scenario: specials placed elsewhere or declined
- **WHEN** a series refers to one special's home in another library and to another special's entry in
  a breakout, and its sidecar declines a third
- **THEN** none of the three is listed as unassigned, and the third is listed among the declined

#### Scenario: a special Wikidata has gained
- **WHEN** Wikidata files beneath a series the library holds, in none of its seasons, an episode
  nothing covers
- **THEN** the special is listed as unassigned, with a suggestion, and not as a missing episode

#### Scenario: a breakout read through the series that refers to it
- **WHEN** a breakout with no Wikidata reference holds entries carrying Wikidata's ids for a series'
  specials, and Wikidata holds an IMDb id for one of them that the breakout's entry lacks
- **THEN** the breakout's differences list that IMDb id against the entry, read through the Wikidata
  items its entries carry

#### Scenario: a container read through nothing
- **WHEN** a container carries no Wikidata id, nothing above it carries one, and none of its items does
- **THEN** its stop says it cannot be read for that reason, and lists no difference

#### Scenario: an entry matched by its other ids
- **WHEN** a held serial's parts carry TheTVDB's ids that Wikidata holds for its parts, and not
  Wikidata's
- **THEN** each part is matched, none is listed as missing or as held only, and each is offered
  Wikidata's id

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aHeldContainersDifferencesFromWikidataAreTakenOrLeft`, `aComparisonSaysWhyItCannotReadAContainer`,
`aSeasonCarryingNoWikidataIdMatchesNothingUntilSaid`, `aHeldStopsEntriesMovedAreStoredInTheirNewOrder`,
`aHeldStopsChildrenAreListedInTheOrderStoringLeavesThem`, `aSeriesSeasonsAreMovedAmongItsChildren`, `aContainerAddedBeneathAStopIsMadeBeneathIt`,
`aHeldSeasonsMissingEpisodesGroupedAreMadeAContainerBeneathIt`,
`aHeldSeasonsMissingEpisodesAreAddedToAContainerHeldBeneathIt`,
`aHeldSeasonsGroupsAreNewStopsBeneathItOnceConfirmed`). The list and its choosing are pinned by nothing
yet, as the rest of the shell is.
