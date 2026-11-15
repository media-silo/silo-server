<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A job made or changed again is answered with the job

## Why
A job made again from its recipe is refused as committed, without the job's id, and a job cancelled,
retried, placed, completed or failed again is refused as the wrong state, as a real wrong state is. So
a client or a node whose answer was lost cannot tell work done from work refused. Each is answered with
the job instead, when the job is as the request asked. Proposal:
[0022-repeats](../../../Proposals/Repeats.md).

## What Changes
- A job made from a recipe whose job the silo holds, of the same kind, is answered 200 with that job;
  of the other kind, 409 naming it; a recipe whose job is gone, 409 saying so.
- A cancel of a cancelled or cancelling job, a retry of a pending job, a place of a placed job, a
  completion that the job already holds and a failure the job already holds are each answered 200 with
  the job.
- Of two copies of one change sent at once, the one that finds the change made is answered with the job.

## Impact
- Modified: a job is made from a resolved recipe; cancelling; retry; placement; completion; a node
  gives a job up; a job's state is checked and changed in one step.
