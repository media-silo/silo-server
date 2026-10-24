<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A held season TMDb's id is not on

## Why
A season imported without TMDb's id matched nothing at TMDb, so its stop was read through the series'
specials and said nothing differed from TMDb's record, and the series offered the season as missing, to
be drafted a second time beside the one the library holds. A stop confirmed twice at once drafted each
season it chose twice. Proposal: [A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A season carrying no TMDb id beneath a series that carries one is said to match nothing at TMDb, with
  TMDb's seasons for the operator to say which it is, the one its title or episodes suggest offered
  first. Said, the season and what is beneath it are read as that season, and its id is chosen.
- A series' stop lists each of TMDb's seasons the library holds beneath it, by its id or as suggested,
  among the children, unchosen and not choosable, and offers none of them as missing.
- An item carrying no TMDb id is matched to TMDb's episode by its other ids.
- A missing child is drafted once, however many times its stop is confirmed.
