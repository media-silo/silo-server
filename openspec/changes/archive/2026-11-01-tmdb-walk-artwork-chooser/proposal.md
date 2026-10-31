<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk's artwork chosen from the images TMDb offers

## Why
A walk offered, for each artwork kind a container lacks, only the image TMDb offers first, and the
operator could take that image or leave the kind without one. TMDb usually offers several images
for a kind, and the first is often not the one wanted. Proposal: [A held tree reviewed against
TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A stop's artwork difference shows every image TMDb offers for the kind, the one storing would put
  marked, TMDb's first until another is chosen.
- Choosing another image ticks the kind, makes the stop pending again, and is the image put when the
  walk is stored.
