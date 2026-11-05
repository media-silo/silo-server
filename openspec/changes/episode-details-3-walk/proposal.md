<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk offers each episode's details, a field at a time

## Why
A library can keep an item's details beside its files, but nothing fills them in. Wikidata holds each
episode's title, first air date, cast, directors and writers as CC0 statements, in the season reading
0020 has the walk make, and TMDb holds its overview, which is content. The operator should take each
field or leave it, as with every other difference. Proposal:
[An episode's details](../../../Proposals/EpisodeDetails.md), step 3, on
[Facts from Wikidata, content from TMDb](../../../Proposals/Wikidata.md).

## What Changes
- Wikidata's reading of a season reads each episode's label, publication date, cast with characters,
  directors and screenwriters, and the people's ids.
- Each episode's outline is TMDb's overview, read through the TMDb episode id Wikidata holds.
- Every stop whose container holds an episode the reading has offers an *Episodes* group of five
  fields: title, outline, air date, cast, and directors and writers. Each is chosen for all the stop's
  episodes at once, or an episode at a time.
- Storing the walk puts each episode's details after its container's edit or creation, with the chosen
  fields replaced and the outline attributed to TMDb with the date it was read.
