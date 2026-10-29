<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Confirm and Next, and Close and Save

## Why
Walking a tree is mostly confirming the open stop and going on to the next, two clicks each time:
on the first stop not yet confirmed Next was disabled until Confirm was pressed. And the walk's Close
kept the walk on this Mac without saying so, so closing read as possibly losing it. Proposal:
[A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- On the first stop not yet confirmed, Next is Confirm and Next: it confirms the stop as Confirm does,
  saying first any new containers confirming takes out of the walk, and opens the next stop once
  confirmed.
- Close is Close and Save, and says it keeps the walk on this Mac, nothing stored in the silo.
