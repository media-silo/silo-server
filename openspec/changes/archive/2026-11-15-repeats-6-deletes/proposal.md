<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A delete or a library's add sent again is answered as made

## Why
A library removed, a recipe discarded or a trial deleted again is 404, as an id that never existed is,
and a library added again is 409, as an id another library holds is. The silo keeps a record of what it
deleted, so a delete sent again is answered as made while a mistyped id is still refused, and a library
added again at its path is answered with it. Proposal: [0022-repeats](../../../Proposals/Repeats.md).

## What Changes
- The silo records each library, recipe and trial it deletes, by id, for thirty days, in
  `deleted.json` in its state directory.
- A delete of an id the record holds is answered 204; one never held, or deleted longer ago, is 404.
- A library added again under its id at its path is answered 200 with it; at another path, 409 as now.

## Impact
- Added: the silo remembers what it deleted.
- Modified: libraries are added and removed over the network; a recipe is committed once; trials are
  listed, served, fetched again and deleted.
