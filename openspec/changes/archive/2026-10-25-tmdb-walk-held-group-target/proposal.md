<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A container held beneath is among a held stop's children, and its missing episodes may join it

## Why
A held season's children listed only the episodes it lacks and the groups made of them: a serial the
season held beneath it already showed nowhere until the season was confirmed, and then only as its
own stop, which said nothing differs. A missing part of a held serial could only be added to the
season itself or grouped into a new serial beside the one held. Proposal:
[A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A held stop's reading finds the containers it holds beneath it, each shown among its children at
  the place of the first of TMDb's episodes it holds.
- Its missing episodes may be added to one of them as to a group made there, taken out again, or
  grouped instead; storing the walk adds them to that container, in its own stop's edit once that is
  confirmed, and what TMDb puts after them follows the container.
- The held container's stop lists what was added to it among its children, each only to be taken
  out again.
