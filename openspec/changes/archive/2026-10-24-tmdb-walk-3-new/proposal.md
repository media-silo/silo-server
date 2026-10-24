<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# New containers in the walk

## Why
A season the library does not hold exists only once its draft from TMDb is created, in a sheet of its
own, so nothing can be placed in it while the walk is reviewed. Proposal: [A held tree reviewed against
TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A missing child chosen at a stop joins the walk as a new stop, a draft from TMDb with TMDb's fields,
  references and artwork chosen to begin with.
- A new stop is shaped as a draft from TMDb is, and what the shaping makes beneath it are new stops.
- Specials can be placed in a new stop, and the store creates each new container before anything that
  refers to it.
- Unchoosing a missing child removes its stop and everything beneath it from the walk.
