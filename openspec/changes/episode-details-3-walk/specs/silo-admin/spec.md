<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A walk offers each episode's details from TMDb, a field at a time
A reading of a season, held or drafted, SHALL read with it each episode's overview, air date, guest
stars and crew, and the season's regular cast; a reading SHALL go on without them when TMDb does not
answer. An episode's details from TMDb SHALL be its title, its overview as the outline, its air date,
its cast as the season's regular cast followed by the episode's guest stars, each with the character
they play, and its crew as the jobs TMDb files under directing and writing, each with the job, and each participant
carrying TMDb's id for the person as a `tmdb` reference. A stop
whose container holds an entry carrying the TMDb id of an episode the reading has SHALL offer an
*Episodes* group of five fields: title, outline, aired, cast, and directors and writers. A field SHALL
be offered for an episode when TMDb has a value for it and the library's details of the episode lack
the field or differ from TMDb's. Each field SHALL be chosen for every episode of the stop at once, the
field showing when only some of its episodes are chosen, and each episode's fields SHALL be chosen one
at a time. At a held stop none SHALL be chosen to begin with, and at a new stop every one SHALL be. The
choices SHALL be kept with the walk, and changing one at a confirmed stop SHALL make it pending again.
Storing the walk SHALL put the details of each episode with a field chosen, after its container's edit
or creation: the library's details of the episode as they stood, with each chosen field replaced by
TMDb's, and the outline, when chosen, attributed to the episode's TMDb id.

#### Scenario: the air dates of a held season
- **WHEN** a held season whose episodes have no details is walked, the stop's air date field is chosen
  and the stop confirmed
- **THEN** storing the walk puts details for each episode holding its air date and nothing else

#### Scenario: one episode's cast left as it was
- **WHEN** a held season's episodes have details with a cast, TMDb lists a different cast for each, the
  stop's cast field is chosen and then unchosen for one episode, and the stop confirmed
- **THEN** storing the walk puts every other episode's details with TMDb's cast, and leaves that
  episode's cast as the library held it

#### Scenario: a new season's details
- **WHEN** a missing season is chosen at a held series' stop, and its new stop is confirmed as it is
- **THEN** storing the walk makes the season, and then puts each episode's title, outline, air date, cast
  and crew, the outline attributed to the episode's TMDb id

#### Scenario: only directors and writers offered
- **WHEN** TMDb lists an episode's director, writer, editor and composer
- **THEN** the episode's directors and writers field offers the director and the writer alone, each with
  their TMDb person id as a `tmdb` reference

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aHeldSeasonsEpisodeDetailsAreOfferedAField`,
`anEpisodesFieldUnchosenIsLeftAsTheLibraryHeldIt`, `aNewSeasonsEpisodeDetailsArePutOnceItIsMade`);
`Tests/SiloAdminKitTests/TMDbClientTests.swift` (`aSeasonIsReadWithItsEpisodesCreditsAndOverviews`).
The sheet's *Episodes* group is pinned by nothing yet, as the rest of the shell is.
