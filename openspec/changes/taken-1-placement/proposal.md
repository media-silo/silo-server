<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Placement is taken at once, and made in the background

## Why
Placing a job fetches its output inside the request, which can take minutes, and a job left `placing`
by a stop is never placed. Proposal: [0023-taken](../../../Proposals/Taken.md). Tracking issue:
silo-server#197.

## What Changes
- A place sets the job `placing`, queues it and answers 202 with the job; the job says how it ended.
- A place sent while the job is `placing` is answered 202 with the job, and placed once.
- A job left `placing` at a start is queued to be placed again, from a whole staged copy when there is
  one.
- A placement refused, or a node that does not give the output, is the job's failure, not 409 or 502.
- `silo-ctl jobs place` reads the job until it is no longer `placing`.

## Impact
- Modified: placement; the operator drives the queue with `silo-ctl jobs`.
