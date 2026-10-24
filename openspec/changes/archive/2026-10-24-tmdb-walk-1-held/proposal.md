<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk through what the library holds

## Why
0017's differences belong to the container they were opened on, so a series and everything beneath it
is reviewed a sheet at a time from the browser, with nothing recording which have been looked at, and
a series' specials are placed from the series without the container they go in in view. Proposal: [A
held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- Opening a held container's differences starts a walk rooted at it, whose first stop is the
  container.
- Confirming a stop keeps its chosen differences as a pending change and queues the containers the
  library holds beneath it, in the tree's order.
- The walk's tree is shown with each stop's state, and any stop can be opened again and confirmed
  again.
- A series' unassigned specials are shown beside every stop and can be placed in the open stop.
- Nothing is stored until the walk is: the store lists every creation, edit and put first, makes them
  in order, and stops at the first refusal.
