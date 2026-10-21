<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Edits move folders, and a library is laid out again

## Why
A presentation's id no longer depends on its path, so the silo can keep a library's folders named and
numbered as their containers are. An edit renames the folders it changes, and an operator can lay a
whole library out again. Proposal: [Folders in their order](../../../Proposals/FolderOrder.md), step 2.

## What Changes
- An applied edit renames the container's folder when its title changes, and renumbers the folders of its held children whose positions change, recording each new path in the sidecar that names the child and re-reading what moved.
- The edit's result, and its dry run, list the moves; a rename that fails is a warning, and the edit is still applied.
- `POST /v1/libraries/{library}/layout` renames every folder not named as the layout gives it, top down, with a dry run.
