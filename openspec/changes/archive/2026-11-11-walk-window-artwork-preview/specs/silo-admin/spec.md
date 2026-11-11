<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A container's artwork is shown, put and removed from the console
SiloAdmin SHALL show, for a container, each artwork kind its folder holds, and SHALL let the
operator put an image as a kind — dropped onto it, or chosen — and remove a kind, through the
library's artwork routes. For a container whose TMDb record the console finds, as its differences
from TMDb find it, SiloAdmin SHALL let the operator browse TMDb's images for the record — its posters
for `poster`, its backdrops for `fanart` and its logos for `logo` — and put one, with its
attribution to `tmdb` and the record's id. A kind whose image is attributed SHALL be shown with its
attribution, and an image dropped or chosen from this Mac SHALL be put with none, removing any the
kind had. A refusal SHALL be shown in words. Every image of artwork the console shows, a
container's own and those TMDb offers, in a walk or not, SHALL be shown whole in Quick Look when it
is double-clicked, or when Space is pressed with the pointer over it and no text being edited, and
Space SHALL close it again.

#### Scenario: a poster seen whole
- **WHEN** the operator presses Space with the pointer over one of TMDb's posters offered for a
  container
- **THEN** the poster is shown whole in Quick Look, and Space closes it

#### Scenario: a poster dropped
- **WHEN** the operator drops a JPEG onto a container's poster
- **THEN** the image is put, and the container shows the poster the silo serves

#### Scenario: a poster taken from TMDb
- **WHEN** the operator puts one of TMDb's posters for a film the library holds by its TMDb
  reference
- **THEN** the container shows the poster the silo serves, credited to TMDb

#### Scenario: a TMDb poster replaced with the operator's own
- **WHEN** the operator drops a JPEG onto a poster credited to TMDb
- **THEN** the container shows the new poster, credited to no one

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainersAreBrowsedAndEditedFromTheConsole`,
`artworkIsTakenFromTMDbWithItsAttribution`), and `Tests/SiloAdminTests/ArtworkPreviewTests.swift`
(`anImageIsNamedForWhatItsBytesAre`). Dropping and choosing an image, and seeing one whole, are
pinned by nothing yet, as the rest of the shell is.

### Requirement: A companion series of the operator's own is a stop of a walk
Beneath the walk's tree, the console SHALL offer to add a companion series of the operator's own
beside the walked series, with the title the operator gives it, unlisted to begin with and listed
when the operator says, holding nothing yet. A new companion series made for a special as it is
placed SHALL be one too. Each SHALL be a new stop of the walk with no stop above it, listed after
the root's tree in the order the companions were added, and the walk's tree SHALL show it as a new
companion series. It SHALL be opened, shaped and confirmed as any new stop is: specials SHALL be
placeable in it, alternatives drafted for it, extras dropped on it, and new containers added beneath
it, each a new stop beneath it once it is confirmed. Storing the walk SHALL create a confirmed
companion series, with the containers beneath it in one creation, at the top of the library before
anything else the walk makes, holding after its own entries each entry placed in it from another
stop. A companion series not confirmed SHALL make nothing, nor SHALL a special placed in it from
another stop make an entry in it or a reference to that entry. The operator SHALL be able to take a
companion series out of the walk, which SHALL take every stop beneath it out too, SHALL unassign
again the specials placed in it or beneath it and those placed in it from another stop, and SHALL
make those other stops pending again. A walk kept before companion series were stops SHALL be read
with each new companion series it made as a stop of its own, confirmed.

#### Scenario: a companion series added
- **WHEN** a companion series is added to a walk of a held series
- **THEN** it is a pending new stop with no stop above it, listed after the series' tree

#### Scenario: a companion series stored
- **WHEN** a special is placed as an entry of a new companion series, a collection is added beneath
  it, another special is placed in it from a season, and the companion series, the collection and
  the season are confirmed and the walk is stored
- **THEN** the companion series is created first, at the top of the library, with the collection
  beneath it, holding the collection, the first special's entry, then the second's, and the
  season's edit refers to the second special's entry

#### Scenario: a companion series not confirmed
- **WHEN** a special is placed in a new companion series from a season, and the season is confirmed
  and the companion series is not
- **THEN** storing the walk makes nothing of the companion series, and the season's edit refers to
  nothing in it

#### Scenario: a companion series taken out
- **WHEN** a companion series holding a container beneath it, one special placed in it and another
  placed in it from a season, is taken out of the walk
- **THEN** its stop and the container's leave the walk, both specials are unassigned again, and the
  season's stop is pending again

#### Scenario: a walk kept before companion series were stops
- **WHEN** a walk kept with a new companion series made for a special is read
- **THEN** the companion series is a confirmed stop of the walk, which storing the walk creates

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aCompanionSeriesIsAStopOfItsOwn`,
`aWalkKeptBeforeCompanionsWereStopsReadsThemAsStops`). The walk's view is pinned by nothing yet, as
the rest of the shell is.

### Requirement: A record the library does not hold is walked from a draft of it
Picking a Wikidata item that neither smddb's clone nor the library holds SHALL start a walk rooted at
the draft's top, shown as a walk of a held tree is: the walk's tree, the open stop and,
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
`aSeriesSpecialsArePlacedFromThePool`). The walk's view, the offer to resume, and starting again are pinned by nothing yet, as the rest of
the shell is.

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
`aContainerAddedToADraftIsAnEmptyGroupMadeWithIt`). The search, and the walk the draft is shaped in,
are pinned by nothing yet, as the rest of the shell is, but for where a child dropped where it is goes: `Tests/SiloAdminTests/GroupingSuggestionTests.swift` (`aChildDroppedWhereItIsStays`).

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
the walk on this Mac. The walk SHALL take the console's window while it lasts, in place of what the
window shows, and closing it SHALL give the window back as it was. The console SHALL show the walk's tree as far as the
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
`aSpecialDroppedAmongAStopsChildrenIsPlacedBeforeTheChild`). The walk's view is pinned by nothing yet, as the rest
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
`aNewStopsEntryMovedIsStoredWhereItWasMovedWithWhatFollowedIt`). The walk's view is pinned by nothing
yet, as the rest of the shell is, but for what a moved child reads from a drop:
`Tests/SiloAdminTests/GroupingSuggestionTests.swift` (`aChildDraggedIsReadBackFromItsText`).
