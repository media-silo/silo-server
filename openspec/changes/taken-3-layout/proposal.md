<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A library's layout is taken at once, and recorded

## Why
Laying a library out renames its folders and walks it inside the request. Proposal:
[0023-taken](../../../Proposals/Taken.md). Tracking issue: silo-server#197.

## What Changes
- A layout records itself under way, is queued and answered 202; `GET /v1/libraries/{library}/layout`
  answers the last layout, with its moves and findings once made.
- A layout asked for while one is under way is answered with it, and made once.
- A layout recorded under way at a start is made again.
- A dry run is answered with its moves as now, and records nothing.
- The console's layout sheet reads the record until the layout is made.

## Impact
- Modified: a library is laid out again on request; the console lays a library out again.
