<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A placement and a branch made again are answered as made

## Why
A file placed again is refused as a collision with another file is, without its presentation's id; a
branch started again is refused as a name taken is; and a branch promoted again is refused as closed.
Each is answered as made instead, when what the library or the ruleset holds is what the request asked
for. Proposal: [0022-repeats](../../../Proposals/Repeats.md).

## What Changes
- A placement whose presentation the library holds at the path it would write, with the tracks and
  chapters it asks for, is answered 200 as applied, with that presentation's id and no writes.
- A branch started again from the same base is answered 200 with the branch as it stands; from another
  base, 409 as now.
- A branch promoted again is answered 200 with the standard's version its promotion made.

## Impact
- Modified: a refused placement is answered whole; a ruleset's branches are listed, started, stored on
  and promoted; promotion makes a branch's head the standard's next version.
