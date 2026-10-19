<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Libraries, step 5: Checking a path, and making its folders

## Why
The console cannot browse the silo's disk, so a folder typed within a root was learned to be missing
only from a refusal, and could be made only at the machine. A follow-up to the four steps. Proposal:
[Libraries](../../../Proposals/Libraries.md).

## What Changes
- `POST /v1/libraries/check` answers what an addition would find along its path, and the refusal it would meet, adding nothing.
- `POST /v1/libraries` takes `create`, making the missing folders within a root that exists; a root is never made.
- The console's add sheet shows each folder along the path as it is typed, and offers to make the missing ones.
