<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Confirming a stop says it is as it should be

## Why
Confirming a stop was meant as the operator's own marker: this is as it should be, and the walk need
not come back to it before storing. It worked as a snapshot instead. A stop changed after it was
confirmed kept its badge while storing used what it had taken before, so confirming again was the
only way to bring the two together, and the badge, changed or looked at, read as a version rather than
a state. The badge also followed the ticks rather than the store: a new season with TMDb's year ticked
was changed, and a serial beneath it, with nothing of its own to tick, looked at, though storing makes
both. A group of a held stop's missing episodes was made whether or not its own stop was confirmed,
and a new season's serial was made with the season whether or not it was. Proposal:
[A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A stop's badge says what storing would do with it: pending; or confirmed, and it will be created,
  created once a stop above it is confirmed, edited, or left unchanged, read from the store's plan.
- Any change to a confirmed stop's choices makes it pending again, its choices kept; the stop's
  header confirms it, or unconfirms it, which does the same as a change.
- A new container is made only once it and every new container above it are confirmed, a held stop's
  groups and a new season's serials included.
