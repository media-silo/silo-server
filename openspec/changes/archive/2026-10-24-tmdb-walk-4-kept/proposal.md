<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk kept on this Mac

## Why
A walk through a long series is hours of work, and is work in progress as a draft is, so it outlives
the console being closed, and an edit it makes of a sidecar that changed meanwhile must not overwrite
the change. Proposal: [A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A walk is kept on this Mac until it is stored or discarded, and is resumed or started again from the
  differences of the container that roots it.
- An edit whose sidecar changed after its stop read it is refused, and its stop is read again.
