<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A held season carrying no TMDb id matches nothing until the operator says which it is
A season beneath a series that carries a `tmdb` reference, and that carries none itself, SHALL match
nothing at TMDb: its stop SHALL say so, and SHALL list the series' seasons at TMDb for the operator to
say which it is, the one suggested chosen to begin with. The season SHALL be suggested to be the one
TMDb names as its title is, else the one whose number its title gives, as `Season 13` gives 13, else
the one TMDb finds an episode beneath it in by the episode's other ids. Until the operator says which,
nothing SHALL be read against the season, and a container beneath it SHALL be read through nothing and
say why. Once the operator says which, the season, and every stop beneath it, SHALL be read again as
that season, its stop pending again, and the season's TMDb id SHALL be offered and chosen. The operator
SHALL be able to say it is unmatched again. A series' stop SHALL list, among its children, each of
TMDb's seasons the library holds beneath it, by its `tmdb` reference or as the season suggested for a
held season carrying none, saying which; such a season SHALL be a stop of the walk whatever is chosen,
SHALL NOT be choosable, and SHALL NOT be offered as missing. An item carrying no `tmdb` reference SHALL
be matched to the episode TMDb finds by its other ids, and SHALL NOT be listed as held only or its
episode as missing; one held at the stop's own level SHALL be offered TMDb's id.

#### Scenario: a season imported without TMDb's id
- **WHEN** a series holds a season titled with its number and no TMDb id, holding one of TMDb's two
  serials for that season
- **THEN** the series' stop lists TMDb's season as perhaps the held one, offering it as missing nowhere,
  and the season's stop says it matches nothing at TMDb, suggesting TMDb's season of that number

#### Scenario: the operator says which season it is
- **WHEN** the operator says the season is TMDb's season of that number
- **THEN** the season's stop offers TMDb's id for it, chosen, and lists the other serial's episodes as
  missing, and the serial's stop offers TMDb's ids for the parts that carry only TheTVDB's

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aSeasonCarryingNoTMDbIdMatchesNothingUntilSaid`, `anUnmatchedSeasonIsSuggestedByItsNumberOrItsEpisodes`).
The stop's list of TMDb's seasons is pinned by nothing yet, as the rest of the shell is.

## MODIFIED Requirements

### Requirement: A missing child chosen in a walk is a new container, created when the walk is stored
A missing child chosen at a stop of a walk SHALL join the walk, when the stop is confirmed, as a new
stop beneath it: a draft from TMDb, read as a draft from TMDb reads it, with ids from smddb's client.
It SHALL be drafted once, however many times the stop is confirmed, and the console SHALL take no
second confirm of a stop while one is under way. The walk's tree SHALL show it as new. Its fields and
references, and any artwork TMDb offers for it, SHALL be chosen to begin with. It SHALL be shaped as a
draft from TMDb is shaped, and each container the shaping makes beneath it SHALL be a new stop.
Specials SHALL be placeable in a new stop as in a held one. A new stop SHALL be made only once it is
confirmed: storing the walk SHALL create it through the create route, with the containers beneath it in
one creation, right after the edit of its parent that names it, since the create route makes a
container beneath a parent only once the parent names it. Unchoosing a missing child and confirming its
parent's stop again SHALL remove its new stop and every stop beneath it from the walk, after the
console says which, and the specials placed in them SHALL be unassigned again.

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

#### Scenario: a new season regrouped
- **WHEN** a new season's episodes are regrouped into two serials
- **THEN** each serial is a new stop beneath the season

#### Scenario: a new season unchosen
- **WHEN** a missing season chosen earlier is unchosen, and the series' stop is confirmed again
- **THEN** the season's stop and its serials' stops leave the walk, and a special placed in one of them
  is unassigned again

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aMissingSeasonChosenInAWalkIsANewStop`,
`aStopConfirmedTwiceAtOnceDraftsItsSeasonsOnce`, `aSpecialPlacedInANewSeasonIsCreatedWithIt`,
`aNewSeasonsSerialsAreStopsBeneathIt`, `unchoosingAMissingSeasonRemovesItsStops`). The walk's sheet is
pinned by nothing yet, as the rest of the shell is.
