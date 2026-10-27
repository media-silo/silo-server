<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A held stop's entries moved

## Why
A draft's entries, and a new stop's, could be moved, but a held stop's could not. Its children list
showed only what the library lacks, and storing put each missing episode, group and special where
TMDb's order or the placement put it. Nothing let the operator put a held container's entries in an
order of their own. Proposal: [A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A held stop lists its primary sequence as storing would leave it: what it holds, each episode and
  group taken, each container held beneath, and each special placed in it, those storing adds marked.
- Each entry can be moved before another, or last, by dragging it or from its right-click menu. The
  order is kept with the walk, the stop is pending again, and the stop's edit gets its primary sequence
  in that order.
- An entry the order does not name, as a special placed after the order was given, keeps its place.
- The moves can be undone at once.
