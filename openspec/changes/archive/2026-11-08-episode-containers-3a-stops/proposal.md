<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk drafts each episode as a container, a stop of its own

## Why
An episode is held as a container of its own, with its title, first date and credits as its own
fields, read from Wikidata, and its outline read from TMDb. The walk should draft episodes that way,
read a held one against Wikidata and TMDb at a stop of its own, and store what each stop took.
Proposal: [An episode is a container of its own](../../../Proposals/EpisodeDetails.md), step 3, the
first of its three pull requests, on [Facts from Wikidata, content from TMDb](../../../Proposals/Wikidata.md).

## What Changes
- Wikidata's reading of a season or a serial drafts each episode as an `episode` container beneath
  it, holding its feature, with the episode's title, first date, cast, directors and screenwriters,
  and their ids, and its outline TMDb's overview of it in its season, matched by the TMDb episode id
  Wikidata holds.
- Each episode is a stop. A held one is offered its title, outline, first date, cast, and directors
  and writers where they differ, and one carrying no Wikidata id is read as the episode of its season
  that carries another of its ids.
- A missing episode chosen at a held stop, alone or in a group, is drafted as an episode container, a
  new stop, named after the episode Wikidata puts it after once its stop is confirmed.
- A held season's episode containers are matched by the ids they carry, and are stops beneath it.
- Storing the walk edits each held episode with the fields chosen, its crew of other jobs kept, and
  makes each new one beneath its parent, its outline attributed to TMDb with the day it was read.
