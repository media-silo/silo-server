<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Attributing a container's fields and artwork, and recording what is declined

## Why
The console takes an outline or an image from TMDb, which is a provider's contributors' work and not
a fact, so a library has to record whose it is. The record has to sit somewhere a player can credit it
and an export to smddb can leave it out. A provider's season 0 also lists things the library will
not hold, and the console needs the operator's decline kept, or it offers them forever.
Proposal: [TMDb in the console](../../../Proposals/Tmdb.md).

## What Changes
- A sidecar may attribute its container's outline, an alternative's outline, or an artwork kind to a
  provider and a reference, as a library fact that placements keep.
- An attribution of a field the container lacks is a validator error, and an attributed artwork kind
  with no file is a walk warning.
- A sidecar may record the refs the operator declined, as a library fact that placements keep, and a
  ref both held and declined is a validator error.
- A container's read answers carry its `attributions`.
- `ContainerEdit` and `ContainerCreate` carry attributions of a container's own fields, and the artwork
  `PUT` records or removes a kind's attribution through `provider` and `value`.
- `ContainerEdit` carries `declined`, and `LibraryContainer` serves it; the global container read does
  not.
