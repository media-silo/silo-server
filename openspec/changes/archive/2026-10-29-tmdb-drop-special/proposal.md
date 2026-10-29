<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A special dropped among a container's children

## Why
A special was placed in a container's primary sequence only from its Place menu, a sequence and a
position chosen from a submenu. Dragged onto the children list, where the operator sees the order it
would go into, it did nothing, though the list marked the drop as it would a child's. Proposal:
[A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A special dropped on one of a container's children is placed in its primary sequence before that
  child, and one dropped past the last is placed last, in a draft from TMDb and at a walk's stop alike.
- At a held stop it is listed among the children where it was dropped, moved there as the operator
  would move it after placing it; one placed there already is moved.
- In a new stop, and in a draft, it is placed at the position of the entry it was dropped on.
