<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Libraries, step 2: The server keeps up

## Why
Keeping the index current becomes the server's job: walks at startup, when a library comes back, and every five minutes, joined rather than overlapping; the scan route becomes a read of the last walk. Step 2 of four. Proposal: [Libraries](../../../Proposals/Libraries.md).

## What Changes
- A five-minute walk, and walks on reappearance and on a missing file, coalesced per library.
- A placement the server applies re-reads the sidecars it wrote, waiting on any walk of the
  library, and walks nothing.
- The last walk is kept and read with `GET`; `POST` to the scan route goes.
