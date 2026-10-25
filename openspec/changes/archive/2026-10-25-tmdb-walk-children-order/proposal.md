<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk's tree, and what it makes, in the order a stop's children list them

## Why
A stop's children list puts a held series' seasons in TMDb's order, and a held season's serials and
groups at their first episodes' places, but the walk's tree queued what the library held beneath a
stop in its sidecar's order and every new container after it, by its id, which is random. The tree
read as shuffled, the order the walk opened stops in followed it, and storing named each new season in
its series after the ones held, in the same order. Proposal:
[A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- Confirming a stop queues the stops beneath it, held and new alike, in the order its children list
  them; a stop never read queues what is beneath it in its sequences' order.
- A new container is named in its parent before the first child listed after it that the parent
  names, or last when none is, rather than always last.
