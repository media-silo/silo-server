<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# An item's details, kept beside its files and served with it

## Why
A player has nothing to show on an episode's page: an entry carries its references and no title, and
the silo never asks a provider. The console can read an episode's title, outline, air date and credits,
but the library has nowhere to keep them. The season's sidecar is the wrong place, since it is rewritten
by every edit of the season and the details are the episode's. Proposal:
[An episode's details](../../../Proposals/EpisodeDetails.md), step 2.

## What Changes
- An item may have a details file, `{item}.smd` beside its presentations or `extras/{item}.smd` for an
  extra, named by the `smd` attribute of its `<item>` in the container's sidecar.
- The walk follows an item's `smd`, and reports a details file that does not exist, describes another
  item, is not named as the layout would name it, or is named by nothing.
- A placement and an edit keep an item's details, and an edit that drops an item with details is 422.
- An `Item` in a container's read answers carries its `details`.
- `PUT` and `DELETE` on `/v1/libraries/{library}/containers/{id}/items/{item}/details` put and remove an
  item's details.
