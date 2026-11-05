<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A walk drafts each episode as a container, a stop of its own
Wikidata's reading of a season or a serial SHALL draft each episode it holds as a container of type
`episode` beneath it, in Wikidata's order, holding one sequence `main` of one leaf `feature` of type
`episode`. The episode's container SHALL carry its label as its title, its publication date as its
`premiered`, its cast members as its cast, each with the character they play, its directors and
screenwriters as its crew, with the roles `Director` and `Writer`, a `wikidata` reference and each
provider's id Wikidata holds for it, and for each participant a `wikidata` reference and the TMDb and
IMDb person ids Wikidata holds. Its outline SHALL be TMDb's overview of the episode, read through the TMDb
episode id Wikidata holds, and a reading SHALL go on without it when TMDb does not answer or the episode
has no TMDb id. Each episode SHALL be a stop of the walk, queued when its parent is confirmed as every
child is, listing among its differences each of its title, outline, premiered, cast, and directors and
writers that its provider has a value for and its container lacks or holds differently. A new episode
SHALL be made with its title whatever is ticked. A stop whose container holds episode containers SHALL
offer an *Episodes* group of those five fields, each saying how many of its episodes it would change;
ticking or unticking a field there SHALL tick or untick it at each episode's stop beneath it, and SHALL
confirm nothing. Storing the walk SHALL edit each held episode with a field ticked, after its parent's
edit, with each ticked field replaced by its provider's and the rest as the library held them, and SHALL
make each new episode once its parent is made; an outline ticked SHALL be attributed to the episode's
TMDb id with the date it was read. A special placed in a season's run SHALL be an episode container among
its siblings, and one placed as a version of an episode SHALL be an alternative of that episode's
container, in a sequence of the container's own.

#### Scenario: a season's episodes drafted as containers
- **WHEN** a season Wikidata holds with three episodes is drafted
- **THEN** the draft holds the season with three episode containers beneath it in Wikidata's order, each
  holding its feature and carrying its title, first date and `wikidata` reference

#### Scenario: a field ticked across a season
- **WHEN** a held season whose episodes have no first dates is walked, the premiered field is ticked in
  its *Episodes* group, and the first episode's stop is opened
- **THEN** the first episode's premiered difference is ticked, and unticking it there leaves the other
  episodes' ticked

#### Scenario: a special as a version of one episode
- **WHEN** a special is placed at an episode's stop as a version of the episode, and the stop confirmed
- **THEN** storing the walk adds to the episode's container a sequence holding the special and an
  alternative naming it, and the season's sequences are unchanged

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aSeasonsEpisodesAreDraftedAsContainers`,
`anEpisodesFieldTickedAcrossItsSeason`, `aSpecialAsAVersionIsAnAlternativeOfTheEpisode`);
`Tests/SiloAdminKitTests/WikidataClientTests.swift` (`aSeasonIsReadWithItsEpisodesStatementsAndPeople`).
The sheet's *Episodes* group is pinned by nothing yet, as the rest of the shell is.

### Requirement: A stop is confirmed with everything beneath it in one action
Every stop of a walk SHALL offer *Confirm with everything beneath* beside *Confirm*. It SHALL confirm the
stop with its ticks, then read each stop beneath it, with the progress a reading shows, and confirm each
with the ticks it holds: those the operator set, at the stop or through a group above it, and otherwise
the defaults, nothing at a held stop and everything at a new one. A missing child SHALL be drafted
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
- **WHEN** a season's premiered field is ticked in its *Episodes* group, one episode's premiered is
  unticked at its own stop, and the season is confirmed with everything beneath
- **THEN** storing the walk sets every other episode's first date, and leaves that episode's as the
  library held it

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aNewSeasonConfirmedWithEverythingBeneath`,
`aHeldSeasonConfirmedWithNothingTickedStoresNothing`, `anEpisodesOwnTicksStandThroughTheFastPath`).
The sidebar's *confirmed from above* is pinned by nothing yet, as the rest of the shell is.
