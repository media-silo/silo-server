<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk's stop shows the alternatives storing makes

## Why
A special placed at a stop as another version of the stop's container, or of one of its items, is
stored as a sequence and an alternative naming it. The walk showed neither. The stop listed the special
among those placed there, captioned with the raw id of the item it stands in for, so a placement that
makes a sequence and an alternative read as though it added a special alone. Proposal:
[A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A stop shows its container's alternatives as storing would leave them, pending or confirmed: those it
  holds or its draft has, then those its placed specials make, each with its title and what it plays.
  They are made by the store's own plan, so what is shown is what storing creates.
- A placed special's caption names the item it stands in for by its title.
- A stop's edit in the store's list counts the alternatives it adds, and no longer counts an
  alternative's references to the container's own items as entries.
