<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk drafts episodes as containers, and offers their fields a season at a time

## Why
An episode is held as a container of its own, with its title, first date and credits as its own fields,
read from Wikidata, and its outline read from TMDb. The walk should draft episodes that way and let the
operator take each field at an episode's own stop or for a season's episodes at once, and confirm a
season and everything beneath it in one action rather than visiting every episode. Proposal:
[An episode is a container of its own](../../../Proposals/EpisodeDetails.md), step 3, on
[Facts from Wikidata, content from TMDb](../../../Proposals/Wikidata.md).

## What Changes
- Wikidata's reading of a season or a serial drafts each episode as an `episode` container beneath it,
  holding one leaf, its feature, with the episode's title, first date, cast, directors and screenwriters,
  and their ids, and its outline from TMDb.
- Each episode is a stop, its title, outline, first date, cast, and directors and writers among its
  differences.
- Every stop holding episode containers offers an *Episodes* group of the five fields, ticking a field at
  each episode's stop beneath it.
- Every stop can be confirmed with everything beneath it: each stop beneath is read and confirmed with
  the ticks it holds, the operator's or the defaults, and marked *confirmed from above*.
- Storing the walk edits each held episode with a field chosen and makes each new one beneath its
  season, the outline attributed to TMDb with the date it was read.
- A special placed in a season's run is an episode container, and one placed as a version of an episode
  is an alternative of that episode's container.
- The drafting requirement's entries, which carry references and no title, are replaced with 0020's
  reading deltas, which this step follows.
