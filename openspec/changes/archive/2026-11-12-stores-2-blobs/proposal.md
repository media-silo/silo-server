<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Images held by their digest

## Why
A store puts its images from bytes the console has already sent, so that the request carrying the
store is small and an image is never sent twice. Proposal: [0021-stores](../../../Proposals/Stores.md).

## What Changes
- `PUT /v1/blobs/{digest}` holds a JPEG or a PNG by its SHA-256, refusing bytes that are not the
  digest named; a put of a blob the silo holds is answered as made.
- `GET` on the same path says whether the silo holds the blob, with its size.
- A blob no store under way names is removed a day after it was put.

## Impact
- Added: an image held by its digest.
