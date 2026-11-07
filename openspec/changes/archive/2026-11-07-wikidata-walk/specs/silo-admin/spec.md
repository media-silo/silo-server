<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A container is drafted from Wikidata's item, and shaped before it is created
SiloAdmin SHALL search Wikidata's films, series and collections by title, the most widely known
first, each shown with Wikidata's description of it and its kind. Picking an item whose `wikidata`
reference the clone holds on a container of the same kind SHALL offer that container's import from
smddb, and SHALL NOT draft it. Picking one whose reference a container of the library carries SHALL
NOT draft it, and the console SHALL say the library holds it. Otherwise the console SHALL read the
item as containers, as Wikidata's statements say them: a film as a `movie`; a series as a `series`
with a `season` child for each of Wikidata's seasons of it, or for each of those the operator
chooses; a season as a `season` holding, in Wikidata's order, each of its episodes as an entry and
each of its serials as a `serial` beneath it, holding the serial's parts as entries in Wikidata's
order; and a collection as a `collection` with each of its films as a child. Each container SHALL
carry its item's label as its title, its year where its type has one, a `wikidata` reference, and a
reference for each other provider's id Wikidata holds for it. Each episode's entry SHALL carry the
same references and no title or outline, until the operator titles it. A container's outline SHALL
be the overview of the TMDb record named by the TMDb id Wikidata holds for its item, attributed to
`tmdb` with that id: a film's, a collection's or a series' own, and a season's beneath the series
above it, read by the number TMDb's series gives the season of that id. A container whose item
holds no TMDb id, or whose record TMDb does not answer for, SHALL be drafted with no outline. TMDb's
season 0 SHALL NOT be read: a series' specials are those Wikidata files beneath it.

Each container SHALL be a draft of a new container with an id from the clone's `provisionalID()`,
kept on this Mac with the walk it roots. The top SHALL be filed beneath the container of the
library that carries the reference of the record above it, when there is one, or at the top of the
library. The form SHALL show each episode's title from Wikidata beside its entry, and SHALL store
none. The operator SHALL be able to shape the tree before it is created: re-type a
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
  stop and the season's are confirmed and the walk is stored, the series' sidecar names the season,
  and the library holds the season with an entry for each episode carrying its references and no
  title, and no presentations

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

### Requirement: A series' specials are the episodes Wikidata files beneath it in no season, unassigned until the operator places or declines each
SiloAdmin SHALL read as a series' specials the episodes Wikidata files as the series' and in none of
its seasons, in the order they first aired, each with its Wikidata id, its first date, its title and
each other provider's id Wikidata holds for it, and SHALL show them beside a draft of the series as
unassigned. TMDb's season 0 SHALL NOT be read. The operator SHALL place each special, or not, as one of these:

- an entry in one of the tree's sequences, at a position the operator chooses, or in a container's
  primary sequence by dropping it among the container's children, before the child it is dropped on
  or past the last, and listed among them in its place, moved as they are;
- an extra of the series or of a container beneath it, typed with one of the extra types SmdKit names;
- a child container beneath the series, drafted as a child is;
- a duplicate of an item a library holds, this one or another: the special's home is the film's own
  item or the entry that carries one of the special's ids. The home's entry SHALL carry the special's
  Wikidata id beside its own, and the series SHALL refer to it as `container#item`, from its extras or
  a sequence;
- an entry in a breakout, a companion series of the operator's own beside the series: any series the
  library holds other than the one being drafted or walked, listed or unlisted, or a new one with the
  title the operator gives it, unlisted to begin with and listed when the operator says, created at
  the top of the library before anything that refers to it, and in a walk a stop of its own, created
  once that stop is confirmed; the series SHALL refer to the entry in it, from its extras or a
  sequence;
- an alternative of the container it is placed in, a cut naming the sequence it plays: an entry in an
  alternate sequence the container has, at a position; or an entry in an alternative drafted for the
  container. The operator SHALL be able to draft an alternative of a container with a title, playing
  one special or nothing yet; cloned from one of the container's sequences, playing each item the
  sequence declares or refers to of the container's own, by reference; or cloned from another drafted
  alternative, playing what it plays, its specials included. The operator SHALL be able to place a
  special in a drafted alternative at a position or in place of one of its entries, move its entries,
  take entries out of it, retitle it and discard it. From a drafted alternative's menu, the operator
  SHALL be able to add to it a new container of the kind and title given, holding nothing yet, beneath
  the container and played in its alternatives alone: in a draft, a container of the draft; in a walk, a
  new stop beneath a held stop, not listed among its children since only the alternative plays it, or a container of a new stop's draft and
  a stop once that one is confirmed. Taken out of every alternative playing it, it SHALL leave the draft
  or the walk. A special or a new container in more than one of a container's drafted alternatives
  SHALL be an entry of the first that plays it and referred to from the rest. A
  special replaced, taken out, or in a discarded alternative SHALL leave that alternative, staying placed
  while another still plays it, and a special placed elsewhere SHALL leave every one. Placing a special as a new edition of a container SHALL draft an alternative playing it alone,
  as an omnibus edition is, and placing it as a version of one item SHALL draft one cloned from the
  sequence holding the item with the special in the item's place, as a version of one episode is.
  Making or storing the container SHALL make each drafted alternative that plays anything as a new
  sequence holding its entries in order, each special as an entry carrying its references, each item
  as a reference to it, and each new container made with it as the entry naming it, which none of the
  container's own sequences does, named by a new alternative with its title. A walk or draft kept with a special
  as a new edition or a version SHALL be read with that drafted as an alternative the special is placed
  in;
- declined, which SHALL record the special's ref as declined in the series' sidecar.

For each special the console SHALL pre-fill a suggestion and the reason for it, and SHALL take none
until the operator does. It SHALL suggest, strongest first: where smddb's record of the series files
the special's ref, when the clone holds the series; the breakout that holds the specials before and
after it in the order they aired; a duplicate of the item a library holds that carries one of the ids
other than Wikidata's that Wikidata holds for the special, as its IMDb or TVDB id; a new edition of a
container whose title the special's title names, beside a word such as "Omnibus"; a version of an item
whose title the special's title names beside words such as "Special Edition"; in a
walk, each of these two read from the stops read so far, in place of a weaker suggestion; an entry
between the two episodes the special aired between; and, for a special whose title names it as one,
an extra of the type its title suggests, or declined for a trailer. A special left unassigned
SHALL NOT stop the tree from being created, and creating SHALL hold none of the unassigned. Placing a
special in a duplicate's home or a breakout that the library holds SHALL be an edit of that container,
and the console SHALL list every edit and creation the placements make before it stores any.

#### Scenario: a special that is also a film
- **WHEN** a series' special's IMDb id, which Wikidata holds for it, is carried by a film that another
  library holds, and the operator takes the suggestion
- **THEN** the film's entry carries the special's Wikidata id beside its own, and the series refers to
  that entry

#### Scenario: specials broken out into a series of their own
- **WHEN** the operator files two of a series' specials in a new unlisted breakout, from the extras of
  two serials
- **THEN** the library holds the breakout with an entry for each special carrying its Wikidata id, and
  each serial's extras refer to its entry

#### Scenario: the next special suggested for the breakout
- **WHEN** the specials that aired just before and just after an unassigned special were filed in a
  breakout
- **THEN** the unassigned special is suggested for the same breakout, with that as its reason

#### Scenario: a trailer declined
- **WHEN** the operator declines a special and creates the series
- **THEN** the series' sidecar declines the special's ref, and the library holds no entry for it

#### Scenario: specials left unassigned
- **WHEN** the operator creates a series with every special unassigned
- **THEN** the library holds the series and its seasons, and no special

#### Scenario: a series' specials read from Wikidata
- **WHEN** a series is drafted whose item Wikidata files two episodes beneath, in none of its seasons
- **THEN** the two are the series' unassigned specials, in the order they aired, each with the ids
  Wikidata holds for it, and none of the series' seasons holds them

#### Scenario: an omnibus edition
- **WHEN** a special is placed as a new edition of a serial, titled by the operator
- **THEN** the serial gains a sequence holding only the special's entry, carrying its references, and
  an alternative with that title naming the sequence, and its other sequences are unchanged

#### Scenario: one episode with new effects
- **WHEN** a special is placed as a version of the first of a serial's four episodes
- **THEN** the serial gains a sequence holding the special's entry first and referring to the other
  three episodes, and an alternative naming it, and the serial still holds one entry for each episode

#### Scenario: a container added to a drafted alternative
- **WHEN** a new collection is added to an alternative drafted for a season, the alternative is cloned,
  and the draft is made
- **THEN** the collection is made beneath the season, the alternative's sequence names it, the clone's
  refers to it, and the season's own sequence names it nowhere

#### Scenario: an alternative drafted from a sequence
- **WHEN** a serial's sequence of four episodes is cloned as a new alternative, and one special is put
  in place of the first episode, another added last, the third episode taken out and the fourth moved
  before the second
- **THEN** storing makes one sequence, playing the first special, the fourth and second episodes by
  reference, then the second special, named by an alternative with the alternative's title

#### Scenario: a drafted alternative cloned
- **WHEN** a drafted alternative playing a special in place of a serial's first episode is cloned, and
  the clone has one of the serial's episodes taken out
- **THEN** storing makes both alternatives, the first holding the special's entry and the clone
  referring to it

#### Scenario: a version kept before alternatives were drafted
- **WHEN** a walk kept with a special as a version of a serial's first episode is read
- **THEN** the special is in a drafted alternative that plays it, then the serial's other episodes

#### Scenario: an alternative suggested
- **WHEN** a special's title names a serial beside the word "Omnibus", and another's names one of the
  serial's episodes beside the words "Special Edition"
- **THEN** the first is suggested as a new edition of the serial, and the second as a version of that
  episode, each with that as its reason

#### Scenario: a companion series the library holds
- **WHEN** a special is placed in a listed series the library already holds, referred to from a
  season's extras
- **THEN** that series' edit adds an entry carrying the special's references, the season's extras
  refer to it, and the series stays listed

#### Scenario: a special dropped among a draft's children
- **WHEN** a special is dropped on the second of a drafted season's entries
- **THEN** it is placed in the season's primary sequence at that entry's position, and listed among
  the season's children before the entry

#### Scenario: a new companion series made listed
- **WHEN** a special is placed in a new companion series the operator titles and lists, and the
  companion series' stop is confirmed
- **THEN** the companion series is created listed, holding the special's entry, before the edit that
  refers to it

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aSeriesSpecialsArePlacedFromThePool`,
`aSpecialDroppedAmongAStopsChildrenIsPlacedBeforeTheChild`,
`aContainerAddedToADraftedAlternativeIsNamedInItAlone`,
`aContainerAddedToAStopsDraftedAlternativeIsMadeInItAlone`,
`aSpecialIsSuggestedAsAMoviesDuplicate`, `aSpecialPlacedAsANewEditionIsASequenceOfItsOwn`,
`aSpecialPlacedAsAVersionOfAnEpisodeRefersToTheRest`,
`anOmnibusAndASpecialEditionAreSuggestedAsAlternatives`,
`anAlternativeDraftedFromASequenceIsEditedAndStoredAsLeft`,
`aDraftedAlternativeClonedSharesItsSpecials`,
`versionsKeptBeforeAlternativesWereDraftedAreReadAsDrafts`, `aNewStopsDraftedAlternativesLeaveWithIt`,
`aSpecialIsPlacedInACompanionSeriesTheLibraryHolds`,
`aNewCompanionSeriesIsCreatedListedWhenTheOperatorSays`). The pool and its choosing are pinned by
nothing yet, as the rest of the shell is.

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
of the other ids Wikidata holds for it, and SHALL count as covered when the container, a container
beneath it, or an item the container refers to carries one of them, or when the container's sidecar
declines one. The console SHALL list how the library's sidecar differs from the reading:

- a title or year that differs from Wikidata's, and an outline that differs from TMDb's, the outline
  shown with its attribution;
- each provider's id Wikidata holds that the sidecar lacks, for the container and for each entry it
  holds;
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
SHALL list every edit before it stores any. A chosen child container SHALL join the walk as a new stop
beneath the container. The episodes a held container lacks SHALL be groupable into new containers
beneath it as a draft's entries are, a group of the kind, title and label the operator gives, made
of the episodes selected, its primary sequence going by the id of the held container's as the walk
leaves it, as a draft's entries are, ticked, or added to a group made there already; runs Wikidata titles as the parts of one
story SHALL be suggested as a draft's are, but for a run of the story the held container is titled
as, which is its own parts, and SHALL instead be offered to be titled by its part numbers, as a
draft's own parts are, the entries the walk adds for them carrying those titles. A group SHALL be chosen whole, its episodes shown in it,
each only to be taken out of it or the group ungrouped, each episode then chosen as the group was. A
group chosen SHALL be made, when the walk is stored, as a container beneath the held one holding its
episodes in Wikidata's order, named in the held container's edit where the first of them would have gone,
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
- **THEN** the season's edit adds one entry carrying the episode's references at Wikidata's position,
  and changes nothing else

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

### Requirement: A reading against Wikidata and TMDb says each step as it goes, and shows what it has found
While SiloAdmin reads a held container against Wikidata and TMDb, the console SHALL show the step the reading is
on and, for a step that asks a question of each of several items, how many of them are answered. The
differences found so far SHALL be shown as they are found, and a series' uncovered specials SHALL be
listed as unassigned while their suggestions are read; no difference SHALL be taken until the reading
is over. A reading that fails SHALL say why, with what it found before it stopped. Closing a
container's differences SHALL stop its reading. While a draft's specials' suggestions are read, the
console SHALL show how many are read. SiloAdmin SHALL ask a step's questions of Wikidata, TMDb and
the silo several at once, and no more than six at once. When TMDb answers that too many are being asked, the
request SHALL be asked again after the wait TMDb names, at most three times, before the console says
what TMDb answered.

#### Scenario: a series whose specials are being suggested
- **WHEN** a held series, two of whose seasons and all of whose specials nothing covers, is read
  against Wikidata and TMDb
- **THEN** each step is said as it goes, each counted step counting from none to all of its items, and
  the specials are listed as unassigned while their suggestions are read

#### Scenario: TMDb asked too much at once
- **WHEN** TMDb answers a request twice that too many are being asked, naming a wait of no time,
  and then answers it
- **THEN** the request is asked three times and its answer read; a request TMDb refuses so four times
  is said to have been answered 429

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aComparisonSaysEachStepAsItGoesWithWhatItHasFound`);
`Tests/SiloAdminKitTests/TMDbClientTests.swift` (`tooManyAtOnceIsAskedAgainAfterTMDbsWait`). How
many questions are asked at once, and the sheets' showing it, are pinned by nothing yet.

### Requirement: A held container's tree is reviewed against Wikidata and TMDb as a walk, a container at a time
Opening a held container's differences SHALL start a walk rooted at it, whose first stop is the
container. Confirming a stop SHALL be the operator saying it is as it should be, so that the walk need not come
back to it before it is stored: it SHALL keep its chosen differences as the container's pending change, and
SHALL add as pending stops beneath it each container the library holds beneath it, and each new one,
in the order its children list them, whatever their ids: a series' seasons in Wikidata's order, a held
container's other children each at its place among its missing episodes, and a new container's in
its draft's order; a stop never read SHALL add them in the order its sequences hold them. A stop confirmed with nothing chosen and nothing placed in it SHALL be confirmed and unchanged. Pending stops
SHALL be opened in the tree's order, depth first; open on the first of them, the operator SHALL be
able to confirm it and open the next in one step, and Return SHALL go on to the next stop as that
step or Next does, but while a text field is being edited. Closing the walk SHALL say that it saves
the walk on this Mac. The console SHALL show the walk's tree as far as the
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
something that ties it there: its title naming the stop, an entry of it, the story Wikidata titles an
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
- **THEN** the series is confirmed and unchanged, its three seasons are pending in Wikidata's order, and
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

#### Scenario: a held series' seasons in Wikidata's order
- **WHEN** a held series' sequence holds its seasons out of Wikidata's order, and its stop is confirmed
- **THEN** its seasons are queued beneath it in Wikidata's order

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

### Requirement: A missing child chosen in a walk is a new container drafted from Wikidata, created when the walk is stored
A missing child chosen at a stop of a walk SHALL join the walk, when the stop is confirmed, as a new
stop beneath it: a draft from Wikidata, read as a draft from Wikidata reads it, with ids from smddb's
client, its content read from TMDb through the series above it.
It SHALL be drafted once, however many times the stop is confirmed, and the console SHALL take no
second confirm of a stop while one is under way. The walk's tree SHALL show it as new. Its fields and
references, and any artwork TMDb offers for it, SHALL be chosen to begin with. It SHALL be shaped as a
draft from Wikidata is shaped, its entries moved as a draft's are, each special the walk places among them
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

#### Scenario: a season Wikidata has that the library lacks
- **WHEN** a missing season is chosen at a held series' stop, and the stop is confirmed
- **THEN** the season is a new stop beneath the series, titled as Wikidata titles it, with Wikidata's
  year and references chosen

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

#### Scenario: a season Wikidata puts between two the library holds
- **WHEN** a held series holds Wikidata's first and third seasons, the second is chosen, its stop and the
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

### Requirement: A held season carrying no Wikidata id matches nothing until the operator says which it is
A season beneath a series that carries a `wikidata` reference, and that carries none itself, SHALL
match nothing at Wikidata: its stop SHALL say so, and SHALL list the series' seasons at Wikidata for
the operator to say which it is, the one suggested chosen to begin with. The season SHALL be suggested
to be the one Wikidata labels as its title is, else the one whose number its title gives, as
`Season 13` or `Series 13` gives 13. Until the operator says which,
nothing SHALL be read against the season, and a container beneath it SHALL be read through nothing and
say why. Once the operator says which, the season, and every stop beneath it, SHALL be read again as
that season, its stop pending again, and the season's Wikidata id SHALL be offered and chosen. The operator
SHALL be able to say it is unmatched again. A series' stop SHALL list, among its children, each of
Wikidata's seasons the library holds beneath it, by its `wikidata` reference or as the season suggested for a
held season carrying none, saying which; such a season SHALL be a stop of the walk whatever is chosen,
SHALL NOT be choosable, and SHALL NOT be offered as missing. An item carrying no `wikidata` reference
SHALL be matched to the episode for which Wikidata holds one of its other ids, and SHALL NOT be listed
as held only or its episode as missing; it SHALL be offered Wikidata's id. Once the operator says
which season a held one is, the series' stop SHALL list that season as held by it, as they said, and
a season it was only suggested to be, when they said another, SHALL be listed as missing again, without
the series being read again; a season said to be held SHALL NOT be drafted.

#### Scenario: a season imported without Wikidata's id
- **WHEN** a series holds a season titled with its number and no Wikidata id, holding one of
  Wikidata's two serials for that season
- **THEN** the series' stop lists Wikidata's season as perhaps the held one, offering it as missing
  nowhere, and the season's stop says it matches nothing at Wikidata, suggesting Wikidata's season of
  that number

#### Scenario: the operator says it is another season
- **WHEN** the operator says the season is Wikidata's next season, not the one suggested
- **THEN** the series' stop lists the next season as held by it, and the one suggested as missing

#### Scenario: the operator says which season it is
- **WHEN** the operator says the season is Wikidata's season of that number
- **THEN** the season's stop offers Wikidata's id for it, chosen, and lists the other serial's episodes
  as missing, and the serial's stop offers Wikidata's ids for the parts that carry only TheTVDB's, and
  TheTVDB's ids for the parts that carry only Wikidata's

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aSeasonCarryingNoWikidataIdMatchesNothingUntilSaid`, `anUnmatchedSeasonIsSuggestedByItsTitleOrItsNumber`).
The stop's list of Wikidata's seasons is pinned by nothing yet, as the rest of the shell is.

### Requirement: Content kept longer than its provider's terms allow is offered to be read again, or removed
A held container's outline or artwork kind attributed to a provider whose terms limit how long its
content is kept, as TMDb's six months do, SHALL, once its attribution's `read` is older than that,
be listed among the container's differences whether or not the provider words it otherwise now: the
outline as the provider's overview read again, the same or changed, and the artwork kind as the image
the provider offers first for it now, each to be taken or left as any difference is. Taken, the
outline SHALL be stored with its attribution read today, and the image SHALL be put again with its
attribution read today. When the provider has no overview, or no image for the kind, now, the
difference SHALL say so, and taken it SHALL remove the outline with its attribution, or the kind's
artwork with its attribution, the walk's plan saying which it removes. Left, nothing SHALL change.

#### Scenario: an outline and a poster read again
- **WHEN** a held film's outline and poster were read from TMDb longer ago than TMDb's terms allow,
  TMDb still has both, and the operator takes both and stores the walk
- **THEN** the film's outline is TMDb's overview, and both attributions say they were read today

#### Scenario: an outline and a poster TMDb no longer has
- **WHEN** a held film's outline and poster were read from TMDb longer ago than TMDb's terms allow,
  TMDb now has neither, and the operator takes both and stores the walk
- **THEN** the plan says it removes the film's poster, which TMDb no longer has, and the film is left
  with no outline, no poster, and no attribution

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`contentKeptLongerThanTMDbsTermsAllowIsReadAgainOrRemoved`). The stop's rows for it are pinned by
nothing yet, as the rest of the shell is.

## MODIFIED Requirements

### Requirement: The console reads TMDb with a token kept on this Mac, and credits it
SiloAdmin's settings SHALL take a TMDb read access token, kept in this Mac's keychain and never
written to a file by the app, and a language for TMDb's answers, the Mac's by default. The console
SHALL reach TMDb itself. The silo SHALL NOT be given the token, and SHALL NOT be asked to reach TMDb.
The console SHALL read only content from TMDb, an outline and artwork, and SHALL take
nothing TMDb holds as a fact. With no token, or one TMDb refuses, the console SHALL read no content,
and SHALL say why wherever it would have shown some; it SHALL still search, draft and walk from
Wikidata, a draft holding every fact Wikidata holds and no outline or artwork, and a walk's stops
listing every fact that differs from Wikidata's. A reading that TMDb does not answer SHALL read the
facts alone, and say what TMDb answered. The settings SHALL carry TMDb's logo and the notice that the product uses the TMDb API but is
not endorsed or certified by TMDb. Wherever the console shows something it read from TMDb, it SHALL
mark it as TMDb's.

#### Scenario: no token given
- **WHEN** the console's settings hold no TMDb token
- **THEN** the console reads no outline or artwork from TMDb, and says that no token is given

#### Scenario: a token TMDb refuses
- **WHEN** the console's TMDb token is one TMDb answers as unauthorized
- **THEN** the console reads no outline or artwork from TMDb, and says that TMDb refused the token

#### Scenario: a draft with no token
- **WHEN** a film is drafted with no TMDb token given
- **THEN** the draft holds the film's title, year and every provider's id Wikidata holds for it, and
  no outline, and offers no artwork

#### Scenario: a walk with no token
- **WHEN** a held season that lacks one of Wikidata's episodes, and one of whose entries lacks an
  IMDb id Wikidata holds for its episode, is walked with no TMDb token given
- **THEN** its stop lists the missing episode and the entry's IMDb id, offers no outline or artwork,
  and says that no token is given

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`tmdbIsUnavailableWithoutAToken`,
`aDraftWithNoTMDbHoldsEveryFactAndNoContent`, `aHeldContainersDifferencesFromWikidataAreTakenOrLeft`). The
setting, the keychain and the credit are pinned by nothing yet, as the rest of the shell is.

### Requirement: A record the library does not hold is walked from a draft of it
Picking a Wikidata item that neither smddb's clone nor the library holds SHALL start a walk rooted at
the draft's top, shown in the same sheet as a walk of a held tree: the walk's tree, the open stop and,
for a series, its specials beside every stop. The root SHALL be a new stop with no stop above it in
the walk, opened, shaped and confirmed as any new stop is, its fields and references chosen to begin
with; confirming it SHALL add the containers of its draft beneath it as new stops. A drafted series
SHALL be the series whose specials sit beside every stop, each suggested where it goes as a draft's
specials are, and placed where the draft placed them; a new breakout the draft made for them SHALL be
a companion series of the walk, and the alternatives drafted for the draft's containers SHALL be the
walk's. Storing the walk SHALL make nothing of a root not confirmed. A confirmed root SHALL be
made, with the confirmed containers beneath it and their attributions, in one creation: at the top of
the library, after the walk's companion series and before any other step; or, for a film filed beneath
a collection the library holds, beneath that collection, once that collection's sidecar is edited to
name it. A drafted series SHALL then decline the specials declined in it. A creation the silo refuses
SHALL stop the store there, say why in the silo's words, and keep what was not made, to be stored
again. The walk SHALL be kept on
this Mac as a walk of a held tree is, and picking the same item for the same library again SHALL
offer to resume it or start again, starting again drafting the item afresh.

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

#### Scenario: a drafted root the silo refuses
- **WHEN** a walk rooted at a draft of a film the silo's validator refuses is confirmed and stored
- **THEN** the store makes nothing, says the validator's refusal, and the film's creation is still to
  be stored

#### Scenario: a draft's new breakout
- **WHEN** a series is drafted with two of its specials placed in a new breakout, and the walk rooted
  at the draft is confirmed throughout and stored
- **THEN** the breakout is a companion series of the walk, made at the top of the library before the
  series, holding an entry for each special

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aRecordTheLibraryLacksIsWalkedFromADraft`,
`aWalkFromADraftStartsAndSuggestsAsADraftDoes`, `aDraftTheSiloRefusesIsKeptInItsWalk`,
`aSeriesSpecialsArePlacedFromThePool`). The walk's sheet, the offer to resume, and starting again are pinned by nothing yet, as the rest of
the shell is.

### Requirement: A new stop's artwork is read with its draft and put once it is made
A draft from Wikidata SHALL read, with each container whose item Wikidata holds a TMDb id for, a film,
a series, a collection or a season, the images TMDb holds for that record, a season's through its
series; a draft SHALL be read without them when there is no TMDb token or TMDb does not answer. A new stop SHALL offer each artwork kind TMDb has
an image for, ticked to begin with, and its image SHALL be chosen as a held stop's is. Storing the walk
SHALL put a new stop's ticked artwork after the containers are made, credited to the record it was read
from.

#### Scenario: a missing season's second poster
- **WHEN** a missing season is chosen at a held series' stop, TMDb offering two posters for the season,
  and at the season's new stop the second poster is chosen and the stop confirmed
- **THEN** storing the walk makes the season and then puts the second poster on it, credited to the
  season's TMDb id

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aNewStopsArtworkIsOfferedAndPutOnceItIsMade`).
The new stop's pane showing it is pinned by nothing yet, as the rest of the shell is.

### Requirement: An attribution the console makes says the day its content was read
Each attribution SiloAdmin makes SHALL carry, as its `read`, the day the console read the content it
attributes from the provider: an outline taken into a draft from a provider's record, in a drafted
tree or at a walk's stop, and an image taken from a provider and put as a kind of a container's
artwork, each read on the day it is taken.

#### Scenario: a drafted outline
- **WHEN** a collection is drafted from Wikidata's item, with TMDb's overview as its outline
- **THEN** the draft attributes the outline to TMDb's collection, read today

#### Scenario: an outline taken at a stop
- **WHEN** the operator takes TMDb's outline at a held film's stop and the walk is stored
- **THEN** the film's draft attributes the outline to TMDb's record, read today

#### Scenario: a poster taken from TMDb
- **WHEN** the operator takes one of TMDb's posters for a container
- **THEN** the image is put attributed to TMDb, read today

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aCollectionIsDraftedAndAFilmFiledBeneathTheOneHeld`,
`aFilmsAndACollectionsFieldsAreTakenFromWikidata`, `artworkIsTakenFromTMDbWithItsAttribution`).

## REMOVED Requirements

### Requirement: A container is drafted from TMDb's record, and shaped before it is created
**Reason**: A draft's facts are Wikidata's now, and only its outline and artwork are TMDb's; the
requirement is restated as `A container is drafted from Wikidata's item, and shaped before it is created`, which searches Wikidata, reads a season's serials as Wikidata lists
them, and drops TMDb's episode groups as a series' shape.
**Migration**: None: a draft kept from TMDb is drafted again from Wikidata.

### Requirement: A series' specials are unassigned until the operator places or declines each
**Reason**: A series' specials are read from Wikidata now, as the episodes it files beneath the
series and in none of its seasons, and TMDb's season 0 is no longer read; the requirement is restated as
`A series' specials are the episodes Wikidata files beneath it in no season, unassigned until the operator places or declines each`, whose duplicates are found by the special's other ids in the libraries rather than through
TMDb's lookup, and whose suggestions no longer rest on TMDb's runtimes or episode groups.
**Migration**: None: placements kept by TMDb episode id are made again from Wikidata's specials.

### Requirement: A held container's differences from TMDb are listed, and the operator takes each or leaves it
**Reason**: A held container's facts are read against Wikidata now and its content against TMDb;
the requirement is restated as `A held container's differences from Wikidata and TMDb are listed, and the operator takes each or leaves it`.
**Migration**: None: a container is read through its `wikidata` reference, which a walk offers to
add where Wikidata holds the container's other ids.

### Requirement: A reading against TMDb says each step as it goes, and shows what it has found
**Reason**: A reading asks Wikidata for its facts and TMDb only for content now, so a series'
specials no longer put a question each to TMDb; the requirement is restated as `A reading against Wikidata and TMDb says each step as it goes, and shows what it has found`, without the
scenario of a series with many specials asked of TMDb.
**Migration**: None.

### Requirement: A held container's tree is reviewed against TMDb as a walk, a container at a time
**Reason**: A walk reads its facts from Wikidata and its content from TMDb now, and queues a
series' seasons in Wikidata's order; the requirement is restated as `A held container's tree is reviewed against Wikidata and TMDb as a walk, a container at a time`.
**Migration**: None: a walk kept from TMDb's readings is not read, and the container is walked again.

### Requirement: A missing child chosen in a walk is a new container, created when the walk is stored
**Reason**: A missing child is one of Wikidata's seasons or serials now, drafted from Wikidata;
the requirement is restated as `A missing child chosen in a walk is a new container drafted from Wikidata, created when the walk is stored`.
**Migration**: None.

### Requirement: A held season carrying no TMDb id matches nothing until the operator says which it is
**Reason**: A season is matched by its Wikidata id now; the requirement is restated as `A held season carrying no Wikidata id matches nothing until the operator says which it is`,
which no longer suggests a season by finding one of its episodes at TMDb.
**Migration**: None.
