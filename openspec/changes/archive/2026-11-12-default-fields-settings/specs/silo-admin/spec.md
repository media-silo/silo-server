<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: This Mac's settings say what a new container is ticked with to begin with
SiloAdmin's Settings window SHALL list the fields a new container in a walk may be offered, Wikidata's
year, first date, cast, directors and writers, and references to providers other than Wikidata, and
TMDb's outline and each kind of its artwork, each ticked to begin with, and SHALL let the operator
untick any of them. The settings SHALL be kept on this Mac for every silo. A new stop SHALL be ticked
with every field it is offered but those the settings leave unticked, whenever it joins a walk, a walk
kept on this Mac included; a stop made before the settings changed SHALL keep its ticks. A new
container's Wikidata reference, which the library knows the item by, SHALL be ticked whatever the
settings say, and a held stop SHALL be ticked with nothing to begin with, as before. A field left
unticked SHALL still be offered at each stop, to be ticked there.

#### Scenario: a film's outline left unticked
- **WHEN** the settings leave the outline and other providers' references unticked, and a film whose
  item holds a TMDb id is drafted
- **THEN** the film's stop offers its outline and its TMDb reference, neither ticked, and its Wikidata
  reference ticked

#### Scenario: the settings changed during a walk
- **WHEN** the settings come to leave references unticked during the walk of a drafted series, and the
  series' stop is then confirmed
- **THEN** each season's new stop offers its TMDb reference unticked, and its Wikidata reference ticked

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aNewStopIsTickedAsThisMacsDefaultsSay`).
The Settings window is pinned by nothing yet, as the rest of the shell is.

## MODIFIED Requirements

### Requirement: The console reads TMDb with a token kept on this Mac, and credits it
SiloAdmin's Settings window, this Mac's settings for every silo, SHALL take a TMDb read access token, kept in this Mac's keychain and never
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
the draft's top, shown as a walk of a held tree is: the walk's tree, the open stop and,
for a series, its specials beside every stop. The root SHALL be a new stop with no stop above it in
the walk, opened, shaped and confirmed as any new stop is, its fields and references chosen to begin
with but those this Mac's settings leave unticked; confirming it SHALL add the containers of its draft beneath it as new stops. A drafted series
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

### Requirement: A new stop's artwork is read with its draft and put once it is made
A draft from Wikidata SHALL read, with each container whose item Wikidata holds a TMDb id for, a film,
a series, a collection or a season, the images TMDb holds for that record, a season's through its
series; a draft SHALL be read without them when there is no TMDb token or TMDb does not answer. A new stop SHALL offer each artwork kind TMDb has
an image for, ticked to begin with unless this Mac's settings leave the kind unticked, and its image SHALL be chosen as a held stop's is. Storing the walk
SHALL put a new stop's ticked artwork after the containers are made, credited to the record it was read
from.

#### Scenario: a missing season's second poster
- **WHEN** a missing season is chosen at a held series' stop, TMDb offering two posters for the season,
  and at the season's new stop the second poster is chosen and the stop confirmed
- **THEN** storing the walk makes the season and then puts the second poster on it, credited to the
  season's TMDb id

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aNewStopsArtworkIsOfferedAndPutOnceItIsMade`).
The new stop's pane showing it is pinned by nothing yet, as the rest of the shell is.

### Requirement: A missing child chosen in a walk is a new container drafted from Wikidata, created when the walk is stored
A missing child chosen at a stop of a walk SHALL join the walk, when the stop is confirmed, as a new
stop beneath it: a draft from Wikidata, read as a draft from Wikidata reads it, with ids from smddb's
client, its content read from TMDb through the series above it.
It SHALL be drafted once, however many times the stop is confirmed, and the console SHALL take no
second confirm of a stop while one is under way. The walk's tree SHALL show it as new. Its fields and
references, and any artwork TMDb offers for it, SHALL be chosen to begin with, but those this Mac's
settings leave unticked. It SHALL be shaped as a
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
date, cast, crew and references, each chosen to begin with unless this Mac's settings leave it
unticked, and the episode SHALL be made with its
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

### Requirement: A stop is confirmed with everything beneath it in one action
Every stop of a walk SHALL offer *Confirm and everything beneath* in the menu of its *Confirm* button, whose
own action is *Confirm*, or *Unconfirm* once the stop is confirmed. It SHALL confirm the
stop with its ticks, then read each stop beneath it, with the progress a reading shows, and confirm each
with the ticks it holds: those the operator set at the stop, and otherwise
the defaults, nothing at a held stop and at a new one everything but what this Mac's settings leave
unticked. A missing child SHALL be drafted
beneath a stop only when it is ticked, so the stops confirmed are those its ticks reach. It SHALL place
no special. A stop it confirmed without the operator opening it SHALL be marked *confirmed from above* in
the sidebar until the operator opens it. A stop beneath that cannot be read SHALL be left pending with
its reason, and the rest confirmed. Storing the walk SHALL list everything the action took, as it lists
everything else, before storing any of it.

#### Scenario: a new season and its episodes
- **WHEN** a missing season is chosen at a held series' stop, and the season's new stop is confirmed with
  everything beneath
- **THEN** each of its episodes is confirmed and marked *confirmed from above*, and storing the walk
  makes the season, then each episode with its title, first date, cast and crew, and its outline
  attributed to the episode's TMDb id with the date it was read

#### Scenario: a held season with nothing ticked
- **WHEN** a held season with nothing ticked, at it or at any of its episodes, is confirmed with
  everything beneath
- **THEN** each of its episodes is confirmed with nothing taken, and storing the walk stores nothing for
  them

#### Scenario: an episode opened first keeps its own ticks
- **WHEN** one of a held season's episodes has its premiered ticked at its own stop, and the season is
  confirmed with everything beneath
- **THEN** storing the walk sets that episode's first date, and leaves every other episode's as the
  library held it

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aNewSeasonConfirmedWithEverythingBeneath`,
`aHeldSeasonConfirmedWithNothingTickedStoresNothing`, `anEpisodesOwnTicksStandBeneathItsSeason`).
The sidebar's *confirmed from above* is pinned by nothing yet, as the rest of the shell is.
