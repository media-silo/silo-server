<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A source's natural key is required

## Why
A source registered without a natural key is never matched, so registering one again because the first
answer was lost makes a second source of the same file. With the key required, every repeat finds the
source the first made. Proposal: [0022-repeats](../../../Proposals/Repeats.md).

## What Changes
- `POST /v1/sources` without a natural key is 400, and registers nothing.
- A producer that knows no identity of its own for a file sends its content hash as the key.

## Impact
- Modified: a source is registered with its input spec; a natural key finds the source already
  registered.
