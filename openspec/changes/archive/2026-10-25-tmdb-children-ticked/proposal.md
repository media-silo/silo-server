<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A container's children ticked alike, held or new

## Why
A held container's children were ticked to be taken, while a new one's entries were selected only to
be grouped, every one made whatever was selected. The two lists looked alike and meant different
things, and the operator could not leave an entry of a new container out. Proposal: [A held tree
reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A new container's entries, and its groups as one each, are ticked to be made, all ticked to begin
  with; one unticked is left out when it is made, a group with everything in it.
- An entry naming a container the library holds already is shown ticked, and cannot be unticked.
- Both lists say how many of their children are ticked in their heading, which ticks them all or none.
- A group unticked in a new stop leaves the walk, as one ungrouped does, and is a stop again once
  ticked and its new stop confirmed again.
