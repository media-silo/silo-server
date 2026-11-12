<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A walk drafts each episode as a container, a stop of its own
Wikidata's reading of a season or a serial SHALL draft each episode it holds as a container of type
`episode` beneath it, in Wikidata's order, holding one sequence `main` of one leaf `episode` of type
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
  each holding its episode and carrying its title, first date and references, and only the first an
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

### Requirement: A special placed among a season's episodes is an episode container
A special placed in the run of a season or serial whose episodes are containers SHALL be an episode
container of its own where it was placed, holding its one episode, with its title, first date, cast,
crew and references Wikidata's, made after the edit of the container it was placed in. A season or
serial holding an episode as an entry of its own SHALL take a special placed in it as an entry of its
own. A special placed as a version of an episode SHALL be an alternative of that episode's container,
in a sequence of the container's own, whether it was placed at the episode's stop or at its season's.

#### Scenario: a special among a season's episodes
- **WHEN** a special is placed between a held season's first and second episode containers, and the
  season's stop confirmed
- **THEN** storing the walk names a new episode container there in the season's edit, and makes it,
  with the special's title, first date, cast and references, holding its episode

#### Scenario: a special as a version of one episode
- **WHEN** a special is placed at an episode's stop as a version of the episode, and the stop confirmed
- **THEN** storing the walk adds to the episode's container a sequence holding the special and an
  alternative naming it, and the season's sequences are unchanged

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aSpecialAmongASeasonsEpisodesIsAnEpisodeContainer`, `aSpecialAsAVersionIsAnAlternativeOfTheEpisode`).
