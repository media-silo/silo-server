<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A primary sequence renamed beneath, and given to the groups made out of its container

## Why
Renaming a container's primary sequence renamed that one container's. A series' seasons and serials
each kept their own, so naming one sequence alike all the way down meant renaming each container in
turn. A group made out of a container's entries had its primary sequence called `parts` whatever the
container's was called, so a season of `episodes` made serials of `parts`. Proposal:
[A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- Renaming a primary sequence can also rename the primary sequence of each container beneath it, at
  any depth. In a walk that is each container the walk knows beneath the stop: those its container
  lists, and the stops beneath it. A held one not yet read is renamed when its edit is made. Each
  container refuses the name alone when another of its sequences has it.
- A group made out of a container's entries, in a draft or of a held stop's missing episodes, has its
  primary sequence go by the id of that container's primary sequence. For a held stop, that is the id
  as the stop's own rename leaves it.
