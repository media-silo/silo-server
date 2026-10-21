<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A held container's differences from TMDb

## Why
A container a library holds drifts from the world: a season gains episodes, a provider id was never
added, a film has no poster. The console lists how a held container differs from TMDb's record, and
the operator takes each difference or leaves it. Proposal: [TMDb in the console](../../../Proposals/Tmdb.md).

## What Changes
- A held container is read against TMDb's record of its reference, or of the nearest container above
  it that has one, and its differences are listed: fields, references, missing children, order and
  artwork.
- Nothing the library holds and TMDb lacks is offered for removal.
- The chosen differences become one edit draft, drafts of new children, and artwork put with its
  attribution.
- TMDb's images are browsed and put from the console with their attribution, and an image of the
  operator's own removes it.
