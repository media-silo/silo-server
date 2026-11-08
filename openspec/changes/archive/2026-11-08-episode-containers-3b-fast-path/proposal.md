<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A season's episodes taken a field at a time, and a stop confirmed with everything beneath it

## Why
With each episode a stop of its own, a season of twenty-six parts is twenty-six stops to tick and
confirm one by one. The operator should be able to take a field for a season's episodes at once, and
confirm a season and everything beneath it in one action. Proposal:
[An episode is a container of its own](../../../Proposals/EpisodeDetails.md), step 3, the second of
its three pull requests.

## What Changes
- Every stop holding episode containers offers an *Episodes* group of their fields, ticking a field at
  each episode's stop beneath it.
- Every stop can be confirmed with everything beneath it: each stop beneath is read and confirmed with
  the ticks it holds, the operator's or the defaults, and marked *confirmed from above*.
