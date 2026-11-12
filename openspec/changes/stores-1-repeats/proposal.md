<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A repeated write is answered as made

## Why
A write whose answer was lost cannot be told from a write that was refused: an edit sent again is a
conflict, containers made again are already held, and a kind removed again is not found, though each
has the effect it asked for. Proposal: [0021-stores](../../../Proposals/Stores.md).

## What Changes
- An edit whose own fields, attributions and declined refs are what the sidecar already holds is
  answered as applied, writing and moving nothing, whatever its base.
- A create whose every container the library already holds, filed where it asks and as it says, is
  answered as applied, writing nothing.
- A removal of an artwork kind the folder does not hold is answered 204.

## Impact
- Modified: a container's own fields edited; a container's artwork put and removed; containers made
  without a file.
