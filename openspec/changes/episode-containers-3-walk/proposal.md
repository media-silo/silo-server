<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk drafts episodes as containers, and offers their fields a season at a time

## Why
An episode is held as a container of its own, with its title, first date and credits as its own fields,
read from Wikidata, and its outline read from TMDb. The walk should draft episodes that way and let the
operator take each field for a season's episodes at once or one at a time, as with every other
difference. Proposal: [An episode is a container of its own](../../../Proposals/EpisodeDetails.md),
step 3, on [Facts from Wikidata, content from TMDb](../../../Proposals/Wikidata.md).

## What Changes
- Wikidata's reading of a season or a serial drafts each episode as an `episode` container beneath it,
  holding one leaf, its feature, with the episode's title, first date, cast, directors and screenwriters,
  and their ids, and its outline from TMDb.
- Every stop holding episode containers offers an *Episodes* group of five fields, each chosen for all
  the stop's episodes or one at a time.
- Storing the walk edits each held episode with a field chosen and makes each new one beneath its
  season, the outline attributed to TMDb with the date it was read.
- A special placed in a season's run is an episode container, and one placed as a version of an episode
  is an alternative of that episode's container.
- The drafting requirement's entries, which carry references and no title, are replaced with 0020's
  reading deltas, which this step follows.
