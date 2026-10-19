<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Libraries, step 1: Missing is a state

## Why
A library whose folder is missing is unavailable rather than fatal: the boot goes on, its index rows are kept, its files answer 503, and the listing says so. Step 1 of four. Proposal: [Libraries](../../../Proposals/Libraries.md).

## What Changes
- The boot no longer stops for a missing library.
- A walk that finds nothing where the index holds something is not applied.
- An unavailable library's media answer 503, and the listing carries `available`.
