<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A trial's fetch is taken at once

## Why
Fetching a trial again fetches its output inside the request. Proposal:
[0023-taken](../../../Proposals/Taken.md). Tracking issue: silo-server#197.

## What Changes
- A fetch clears the trial's failure, queues it on the silo's own fetch queue and answers 202 with the
  job; the job says how it ended.
- A fetch asked for while one is under way is answered 202, and made once; a tried trial is 200.
- A node that does not give the output is the job's failure, not 502.

## Impact
- Modified: trials are listed, served by range, fetched again and deleted.
