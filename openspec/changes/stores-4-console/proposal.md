<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# The console stores a walk as one store

## Why
A walk's store made as one request after another forgets what it made when one of them goes
unanswered, and cannot be sent again without a creation being refused or a placement made twice. Handed
to the silo whole under a key kept with the walk, the store is asked after, not guessed at.
Proposal: [0021-stores](../../../Proposals/Stores.md).

## What Changes
- The list reads each container a placement, a decline or a naming changes, and sends every edit of a
  container as one document on the base it read.
- Storing a walk puts the images the silo does not hold, then sends one store under a key kept with the
  walk before it is sent.
- The store's progress is read from its record at the silo, every second, and again when a walk with a
  key is opened; the store is never sent again under the same key.
- A sidecar changed since the list read it refuses the store before any of it is made.

## Impact
- Added: a walk's store handed to the silo whole.
- Modified: a walk kept until it is stored; a walk's store saying each step.
