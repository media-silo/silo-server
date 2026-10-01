<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Libraries, step 3: Libraries within roots

## Why
Libraries are added and removed over the network, within roots only the machine's owner writes in `silo.json`. Step 3 of four. Proposal: [Libraries](../../../Proposals/Libraries.md).

## What Changes
- `libraryRoots` in `silo.json`.
- `POST` and `DELETE /v1/libraries`, applied while the silo runs.
- The settings route marks the libraries writable.
