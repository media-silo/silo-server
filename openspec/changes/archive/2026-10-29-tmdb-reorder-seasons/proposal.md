<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A series' seasons moved among its children

## Why
A held stop's children were one list the operator could move, but a series' seasons were not in it.
They were ticked in a box of their own and kept the order the series' sequence or TMDb gave them, so
a season the operator wanted elsewhere, or a missing season drafted in, could not be put there.
Proposal: [A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A series' seasons, held and missing, are rows of its children list, in the order storing leaves the
  series' sequence, a missing one ticked there; the box of their own is gone.
- A held season is moved by its entry in the series' sequence, as a serial is.
- A missing season, which no sequence names until it is made, is moved by its place among the stops
  beneath the series, and named there when it is made.
- Until anything is moved, the walk still takes a series' seasons in TMDb's order.
