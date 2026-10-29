<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A child dropped where it already is stays there

## Why
A child dragged by its grab handle and let go over itself was refused as a drop. The refused drag slid
back to where it began, and the console was slow to answer the pointer afterwards. A child dropped on
the one after it, which is where it already is, was moved there all the same, so the moves could be
undone though nothing had moved. Proposal: [A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A child dropped on itself, on the child after it, or past the last when it is last is taken and
  left where it is; no drag of a child is refused.
- Once a child is dropped, nothing stays marked as dragged over or under the pointer.
