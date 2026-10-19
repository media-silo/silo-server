<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A container per library

## Why
A container's id is the same in every library it is filed in, but the index keys its rows on the id
alone, so two libraries' sidecars for one container overwrite each other and removing one takes the
other's presentations with it. The console needs each library's own view of its containers before it
can show or edit them. Proposal: [Containers in the console](../../../Proposals/Containers.md).

## What Changes
- The index keys container, item and external-reference rows by library and container id.
- A library holds a container once; a second sidecar for the same id is an error the walk reports.
- `GET /v1/libraries/{library}/containers`, `…/containers/{id}` and `…/containers/{id}/smd` read a
  library's own view, unlisted containers included.
- `GET /v1/containers/{id}` answers a container held by several libraries from the first in settings
  order, and names the library.
