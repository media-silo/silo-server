<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A node sends again a request lost in transport

## Why
Neither the worker nor silo-node sends a request again, so one dropped connection ends work that was
going well: a progress report lost in transport ends the encode and fails the job, a completion whose
answer is lost is followed by a fail, and a node started while the silo restarts exits. Since
proposal [0022-repeats](../../../Proposals/Repeats.md), the silo answers a request sent again as it
answered the first, so sending one again is safe. Tracking issue: silo-server#196.

## What Changes
- A request lost in transport is sent again after a wait of one second, doubling to thirty, each
  drawn from the upper half of its delay; an answer, a refusal among them, is not.
- A progress report is sent again, the encode running on, until the lease the last answered report
  renewed would lapse; then the encode ends and the job is failed.
- A completion is sent again for up to an hour, and is never turned into a fail.
- silo-node's registration and approval poll are sent again for as long as it takes.

## Impact
- Added: a node sends again a request lost in transport.
- Modified: the loop rides out its errors; silo-node is the node's side of it all.
