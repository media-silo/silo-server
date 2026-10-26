<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A container's primary sequence renamed

## Why
A container's primary sequence goes by an id, such as `parts` for a serial's episodes, which the
operator may want to call something else once alternatives sit beside it. Nothing showed the id, and
nothing renamed it. Proposal: [A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- Under a container's Children heading, its primary sequence is shown by its id, with an actions menu
  to clone it into a new alternative or rename it.
- A name given is kept as an id: lower case, words joined by hyphens. A name another of the container's
  sequences has is refused.
- Renaming renames the alternatives naming the sequence and the specials placed in it, so they still
  name it. A held stop's rename is part of its pending change, makes it pending, and is stored with its
  edit. A new stop's or draft's container is reshaped.
- The other sequences' and drafted alternatives' actions menus sit in their top right corners.
