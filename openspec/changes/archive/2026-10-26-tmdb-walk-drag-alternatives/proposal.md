<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Specials dragged onto a stop's alternatives and extras

## Why
Alternatives are drafted as ordered lists now, but the only way to build one was a menu of menus. A
special went into an alternative by picking an item from one submenu and an alternative from another,
and inserting between two entries or reordering them had no menu at all. Building a list is direct
manipulation, and the stop should show the list being built. Proposal:
[A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A stop's Alternatives box lists each of its container's sequences, each with Clone, and each
  alternative drafted for it, with its entries in order.
- A special dragged onto the box's heading drafts a new alternative playing it, once it is titled.
  Dropped on a drafted alternative's entry, it plays in that entry's place. Dropped between two entries,
  it is added there. A drafted alternative's entries are dragged to reorder them, and each has a button
  to take it out. A drafted alternative can be renamed or discarded.
- A stop's extras are drop targets by kind, and a series' stop has one for declining.
- The same editor serves a draft from TMDb's containers. The menus stay, for the keyboard.
