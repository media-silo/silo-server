<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A special placed among a season's episodes is an episode container
A special placed in the run of a season or serial whose episodes are containers SHALL be an episode
container of its own where it was placed, holding its one feature, with its title, first date, cast,
crew and references Wikidata's, made after the edit of the container it was placed in. A season or
serial holding an episode as an entry of its own SHALL take a special placed in it as an entry of its
own. A special placed as a version of an episode SHALL be an alternative of that episode's container,
in a sequence of the container's own, whether it was placed at the episode's stop or at its season's.

#### Scenario: a special among a season's episodes
- **WHEN** a special is placed between a held season's first and second episode containers, and the
  season's stop confirmed
- **THEN** storing the walk names a new episode container there in the season's edit, and makes it,
  with the special's title, first date, cast and references, holding its feature

#### Scenario: a special as a version of one episode
- **WHEN** a special is placed at an episode's stop as a version of the episode, and the stop confirmed
- **THEN** storing the walk adds to the episode's container a sequence holding the special and an
  alternative naming it, and the season's sequences are unchanged

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aSpecialAmongASeasonsEpisodesIsAnEpisodeContainer`, `aSpecialAsAVersionIsAnAlternativeOfTheEpisode`).
