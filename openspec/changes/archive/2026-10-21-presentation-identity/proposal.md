<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A presentation is named for what it is

## Why
A presentation's id is the hash of its library and its file's path, so a move of the file or of any
folder above it gives it a new id, and a player's resume point, a job's record and the media route all
lose it. The id is now the hash of what the presentation is — its library, container, item,
alternative and profile — so a move changes no id. Proposal:
[A presentation is named for what it is](../../../Proposals/PresentationIdentity.md).

## What Changes
- A presentation's id is the 64-bit FNV-1a hash of its library, container, item, alternative and profile, joined by `|`, rather than of its library and path.
- The walk reports a presentation sharing an id or a file with another in its sidecar as an error and does not index it, where today a shared file stops the walk.
- The media route serves a presentation whose file it found missing from the file a re-read of its sidecar now records, by the same id.
- Nothing is migrated: no silo yet holds a container or a presentation, so no id in the old form is held anywhere.
