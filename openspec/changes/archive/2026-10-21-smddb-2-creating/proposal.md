<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Making containers in a library

## Why
A container enters a library only with a placement, carrying whatever its producer sent. The console
brings containers in from smddb, or creates them, before anything is encoded, so the silo makes a
tree of containers in a library with no file. Proposal: [smddb in the console](../../../Proposals/Smddb.md).

## What Changes
- `POST /v1/libraries/{library}/containers` makes a tree of containers in one library, given as
  repository documents beneath a parent the library holds or at its top, with a dry run.
- A request naming a container the library holds, a parent that does not name the top, or a folder
  holding another container is refused whole with its findings.
- SiloLibrary computes the folders and sidecars of such a tree before making any, new sidecars before
  the parent's, sharing the placer's naming and its update of an existing sidecar.
- What it wrote is re-read into the index, and nothing is walked.
