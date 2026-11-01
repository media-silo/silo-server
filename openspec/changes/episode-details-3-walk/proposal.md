<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk offers each episode's details from TMDb, a field at a time

## Why
A library can keep an item's details beside its files, but nothing fills them in. TMDb holds each
episode's title, overview, air date, guest stars and crew, and the season's regular cast, all in the
season read the walk already makes. The operator should take each field or leave it, as with every other
difference. Proposal: [An episode's details](../../../Proposals/EpisodeDetails.md), step 3.

## What Changes
- The TMDb client reads each episode's overview, crew and guest stars with its season, and the season's
  regular cast.
- Every stop whose container holds an episode TMDb's reading has offers an *Episodes* group of five
  fields: title, outline, air date, cast, and directors and writers. Each is ticked for all the stop's
  episodes at once, or an episode at a time.
- Storing the walk puts each episode's details after its container's edit or creation, with the ticked
  fields replaced and the outline attributed to TMDb.
