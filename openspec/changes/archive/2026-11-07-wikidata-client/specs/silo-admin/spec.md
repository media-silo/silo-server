<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: Wikidata is read without a key, as its policy asks
SiloAdminKit's `WikidataClient`, a `WikidataSource`, SHALL read items' own statements through
Wikidata's API, `wbgetentities`, at most fifty items to a request, and what points at an item and who
people are through Wikidata's query service, by SPARQL. Every request SHALL carry the User-Agent
`Wikidata.userAgent`, naming SiloAdmin and its repository, and no key. Labels and descriptions SHALL be
asked in the language the settings name, then its base language, then `mul` and English, and read in
the first of them that has one. A request answered 429 SHALL be asked again after the wait its
`Retry-After` names, or a second, at most three times, and one whose wait is longer than thirty
seconds SHALL not be waited, the 429 being thrown as `Wikidata.Unavailable.answered`. Reading an item
as a kind it is not an instance of, or of a subclass of, SHALL throw `notA`, and one Wikidata does not
hold `notThere`.

#### Scenario: a film read in the settings' language
- **WHEN** the settings name `en-GB` and a film is read
- **THEN** each request carries SiloAdmin's User-Agent and no `Authorization`, and asks its labels in
  `en-gb`, `en` and `mul`

#### Scenario: too many at once
- **WHEN** every request is answered 429 with `Retry-After: 0`
- **THEN** the request is asked four times, and the 429 is thrown

#### Scenario: a wait too long to keep
- **WHEN** a request is answered 429 with `Retry-After: 600`
- **THEN** it is asked once, and the 429 is thrown

#### Scenario: a series read as a film
- **WHEN** a television series is read as a film
- **THEN** reading throws `notA` naming `film` and the series' id

Pinned by: `Tests/SiloAdminKitTests/WikidataClientTests.swift` (`everyRequestNamesSiloAdminAndAsksInTheSettingsLanguage`,
`tooManyAtOnceIsAskedAgainAfterAWaitThatIsNotTooLong`, `anItemOfAnotherKindOrNoneIsRefused`).

### Requirement: An item is read as a work from its own statements
A film, collection, series, season, serial or episode SHALL be read as a `Wikidata.Work`: its label as
its title, its description, its first date and its year, its references, and its directors (P57),
screenwriters (P58) and cast (P161). Statements SHALL be read as Wikidata's truthy ones are: the
preferred where a property has any, and otherwise every one not deprecated; a credit SHALL be read from
every statement not deprecated. The first date SHALL be the earliest publication date (P577), or start
time (P580) where there is none, that Wikidata knows to the day, and the year the earliest it knows at
all, so that a date known only to its year gives a year and no date. The references SHALL be
Wikidata's own and then, by kind, IMDb's, TMDb's and TVDB's: a film's TMDb movie id, a collection's TMDb
collection id, a series' TMDb and TVDB series ids, a season's TMDb season id, and an episode's TMDb and
TVDB episode ids. Credits SHALL be in the order their editors numbered them (P1545), then in the order
the item lists them, each with the person's label, the character played (P453, or P4633 by name), and
the person's Wikidata, IMDb, TMDb and TVDB ids.

#### Scenario: a day, a year and a preferred id
- **WHEN** a film's statements date it 25 May 1979 to the day, 1978 to the year, and 1 January 1970 in
  a deprecated statement, and give two TMDb movie ids of which one is preferred
- **THEN** the film's first date is 1979-05-25, its year 1978, and its TMDb reference the preferred id

#### Scenario: a film's credits
- **WHEN** *Alien* is read
- **THEN** its director is Ridley Scott, with his TMDb id, and its cast is in the order Wikidata lists
  it, Sigourney Weaver among it playing Ellen Ripley with her IMDb id

Pinned by: `Tests/SiloAdminKitTests/WikidataClientTests.swift` (`anItemsStatementsAreReadAsWikidataMeansThem`,
`aFilmIsReadWithItsCreditsAndItsIDs`).

### Requirement: Wikidata is searched for films, series and collections
`search` SHALL ask Wikidata for up to fifty items whose labels match the text, and SHALL answer those
that are films, television series or film series, each as a `Wikidata.SearchResult` with its kind, its
label, its description and the year it was first shown, the one linked from most Wikipedias first and
otherwise in the order Wikidata found them. An item of two of those kinds SHALL be a series before a
film, and a film before a collection.

#### Scenario: a film, its franchise and a game
- **WHEN** the operator searches for `Alien`
- **THEN** the first result is the 1979 film, the franchise is among them as a collection, and the
  video game of that name is not

Pinned by: `Tests/SiloAdminKitTests/WikidataClientTests.swift` (`aSearchFindsFilmsSeriesAndCollectionsTheMostKnownFirst`).

### Requirement: What an item holds is read in Wikidata's order
A series SHALL be read with its seasons, the items that are part of the series (P179) and are seasons,
in the order of the number the series gives each, then by first date, and those it numbers not after
the rest. A season SHALL be read with the items it is the season of (P4908): those that are parts of a
television season SHALL be read as serials, each holding the season's items that are part of it (P361)
as its parts, and the rest as episodes; a season numbers its serials and its episodes with the same
ordinal, so serials SHALL be ordered by their number among serials and parts by theirs among parts, and
a season holding both serials and episodes of its own SHALL order them by first date. A serial SHALL be
read with the items that are part of it, by the number their season gives them, then in the order the
serial lists them (P527). A collection SHALL be read with the films that are part of it, by the number
it gives each, then by first date.

#### Scenario: a series' seasons
- **WHEN** *Andor* is read
- **THEN** it holds its two seasons, numbered one and two, in that order

#### Scenario: a season of episodes
- **WHEN** *Andor*'s first season is read
- **THEN** it holds twelve episodes from *Kassa* to *Rix Road*, *Kassa* first shown on 21 September
  2022 and carrying its Wikidata, IMDb, TMDb and TVDB ids

#### Scenario: a season of serials
- **WHEN** *Doctor Who*'s thirteenth season is read
- **THEN** it holds six serials, from *Terror of the Zygons* to *The Seeds of Doom*, *Pyramids of Mars*
  third with its four parts in order

#### Scenario: a collection's films
- **WHEN** the *Alien* franchise is read as a collection
- **THEN** its films are in the order they came out, from *Alien* and *Aliens*

Pinned by: `Tests/SiloAdminKitTests/WikidataClientTests.swift` (`aSeriesIsReadWithItsSeasonsInOrder`,
`aSeasonIsReadAsItsEpisodesInOrder`, `aSeasonIsReadAsItsSerialsWithTheirParts`,
`aSerialIsReadWithItsPartsInOrder`, `aCollectionIsReadWithItsFilmsInTheOrderTheyCameOut`).
