<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A walk offers each episode's details, its facts from Wikidata and its outline from TMDb, a field at a time
Wikidata's reading of a season, held or drafted, SHALL read with it each episode's label, publication
date, cast members with the characters they play, directors and screenwriters, and for each person
their Wikidata id and the TMDb and IMDb person ids Wikidata holds. An episode's details SHALL be its
label as its title, its publication date as the date it first aired, its cast members as its cast, each
with the character they play, and its directors and screenwriters as its crew, with the roles
`Director` and `Writer`, each participant carrying its ids as references. Its outline SHALL be TMDb's
overview of the episode, read through the TMDb episode id Wikidata holds for it, and a reading SHALL go
on without it when TMDb does not answer or the episode has no TMDb id. A stop whose container holds an
entry carrying the Wikidata id of an episode the reading has SHALL offer an *Episodes* group of five
fields: title, outline, aired, cast, and directors and writers. A field SHALL be offered for an episode
when its provider has a value for it and the library's details of the episode lack the field or differ.
Each field SHALL be chosen for every episode of the stop at once, the field showing when only some of
its episodes are chosen, and each episode's fields SHALL be chosen one at a time. At a held stop none
SHALL be chosen to begin with, and at a new stop every one SHALL be. The choices SHALL be kept with the
walk, and changing one at a confirmed stop SHALL make it pending again. Storing the walk SHALL put the
details of each episode with a field chosen, after its container's edit or creation: the library's
details of the episode as they stood, with each chosen field replaced by its provider's, and the
outline, when chosen, attributed to the episode's TMDb id with the date it was read.

#### Scenario: the air dates of a held season
- **WHEN** a held season whose episodes have no details is walked, the stop's air date field is chosen
  and the stop confirmed
- **THEN** storing the walk puts details for each episode holding its air date and nothing else

#### Scenario: one episode's cast left as it was
- **WHEN** a held season's episodes have details with a cast, Wikidata lists a different cast for each,
  the stop's cast field is chosen and then unchosen for one episode, and the stop confirmed
- **THEN** storing the walk puts every other episode's details with Wikidata's cast, and leaves that
  episode's cast as the library held it

#### Scenario: a new season's details
- **WHEN** a missing season is chosen at a held series' stop, and its new stop is confirmed as it is
- **THEN** storing the walk makes the season, and then puts each episode's title, outline, air date, cast
  and crew, the outline attributed to the episode's TMDb id with the date it was read

#### Scenario: a director known by id
- **WHEN** Wikidata lists an episode's director, with a TMDb person id
- **THEN** the episode's directors and writers field offers the director with the role `Director`,
  carrying the director's Wikidata id and TMDb person id as references

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aHeldSeasonsEpisodeDetailsAreOfferedAField`,
`anEpisodesFieldUnchosenIsLeftAsTheLibraryHeldIt`, `aNewSeasonsEpisodeDetailsArePutOnceItIsMade`);
`Tests/SiloAdminKitTests/WikidataClientTests.swift` (`aSeasonIsReadWithItsEpisodesStatementsAndPeople`).
The sheet's *Episodes* group is pinned by nothing yet, as the rest of the shell is.
