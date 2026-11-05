<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A walk drafts each episode as a container, and offers its fields a season at a time
Wikidata's reading of a season or a serial SHALL draft each episode it holds as a container of type
`episode` beneath it, in Wikidata's order, holding one sequence `main` of one leaf `feature` of type
`episode`. The episode's container SHALL carry its label as its title, its publication date as its
`premiered`, its cast members as its cast, each with the character they play, its directors and
screenwriters as its crew, with the roles `Director` and `Writer`, a `wikidata` reference and each
provider's id Wikidata holds for it, and for each participant a `wikidata` reference and the TMDb and
IMDb person ids Wikidata holds. Its outline SHALL be TMDb's overview of the episode, read through the TMDb
episode id Wikidata holds, and a reading SHALL go on without it when TMDb does not answer or the episode
has no TMDb id. A stop whose container holds episode containers SHALL offer an *Episodes* group of five
fields: title, outline, premiered, cast, and directors and writers. A field SHALL be offered for an
episode when its provider has a value for it and the episode's container lacks the field or differs.
Each field SHALL be chosen for every episode of the stop at once, the field showing when only some of
its episodes are chosen, and each episode's fields SHALL be chosen one at a time. At a held stop none
SHALL be chosen to begin with, and at a new stop every one SHALL be. A new episode SHALL be made with its
title whatever is chosen. The choices SHALL be kept with the walk, and changing one at a confirmed stop
SHALL make it pending again. Storing the walk SHALL edit each held episode with a field chosen, after its
parent's edit, with each chosen field replaced by its provider's and the rest as the library held them,
and SHALL make each new episode beneath its parent once the parent is made; an outline chosen SHALL be
attributed to the episode's TMDb id with the date it was read. A special placed in a season's run SHALL
be an episode container among its siblings, and one placed as a version of an episode SHALL be an
alternative of that episode's container, in a sequence of the container's own.

#### Scenario: a season's episodes drafted as containers
- **WHEN** a season Wikidata holds with three episodes is drafted
- **THEN** the draft holds the season with three episode containers beneath it in Wikidata's order, each
  holding its feature and carrying its title, first date and `wikidata` reference

#### Scenario: the first dates of a held season
- **WHEN** a held season whose episodes have no first dates is walked, the stop's premiered field is
  chosen and the stop confirmed
- **THEN** storing the walk edits each episode, setting its first date and changing nothing else

#### Scenario: one episode's cast left as it was
- **WHEN** a held season's episodes have a cast, Wikidata lists a different cast for each, the stop's
  cast field is chosen and then unchosen for one episode, and the stop confirmed
- **THEN** storing the walk gives every other episode Wikidata's cast, and leaves that episode's cast as
  the library held it

#### Scenario: a new season's episodes
- **WHEN** a missing season is chosen at a held series' stop, and its new stop is confirmed as it is
- **THEN** storing the walk makes the season, then each of its episodes with its title, first date,
  cast and crew, and its outline attributed to the episode's TMDb id with the date it was read

#### Scenario: a special as a version of one episode
- **WHEN** a special is placed as a version of a season's first episode, and the stop confirmed
- **THEN** storing the walk adds to the episode's container a sequence holding the special and an
  alternative naming it, and the season's sequences are unchanged

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aSeasonsEpisodesAreDraftedAsContainers`,
`aHeldSeasonsEpisodeFieldsAreOfferedAField`, `anEpisodesFieldUnchosenIsLeftAsTheLibraryHeldIt`,
`aNewSeasonsEpisodesAreMadeOnceItIs`, `aSpecialAsAVersionIsAnAlternativeOfTheEpisode`);
`Tests/SiloAdminKitTests/WikidataClientTests.swift` (`aSeasonIsReadWithItsEpisodesStatementsAndPeople`).
The sheet's *Episodes* group is pinned by nothing yet, as the rest of the shell is.
