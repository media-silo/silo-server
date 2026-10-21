<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Moves in the console

## Why
The silo moves folders when an edit renames them and lays a library out on request. The console shows
an edit's moves before it is stored, and lays a library out from its detail. Proposal:
[Folders in their order](../../../Proposals/FolderOrder.md), step 3.

## What Changes
- A container edit's review lists the folders its store would move.
- A library's detail lays the library out again, showing the dry run's moves before applying them.
