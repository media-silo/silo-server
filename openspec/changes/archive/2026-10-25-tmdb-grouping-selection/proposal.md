<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Grouping by selection, apart from the ticks

## Why
A new container's entries are ticked to be made, all of them to begin with, so grouping the ticked
ones left the rest still ticked once a group was made, and leaving them out to start the next group
was the same act as leaving them out of the container. A long list also scrolled its grouping out of
sight. Proposal: [A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A tick only says whether a child is made or taken; grouping works on the entries selected, and
  nothing is selected once a group is made. A group is never selected. A right-click on the selection
  groups it where it is.
- A group is made ticked, since it was selected to be made, whatever its entries were.
- The heading and the grouping's actions stay in sight above a scrolling list, and choosing a new
  group's kind leaves its title ready to be typed.
