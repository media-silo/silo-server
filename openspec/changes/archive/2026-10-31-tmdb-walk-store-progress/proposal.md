<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk's store says each step as it goes

## Why
Storing a walk makes its plan's steps one at a time, and a long plan takes a while, but until it ended
the console said nothing of where it had got to. Proposal: [A held tree reviewed against
TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- While a walk is stored, the console shows the step being made and how many of the plan's steps are
  made before it.
- The store cannot be put off or started again while it is under way.
