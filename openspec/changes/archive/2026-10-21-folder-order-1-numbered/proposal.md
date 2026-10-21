<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Numbered folders, followed by placement

## Why
A library's folders list in the order their titles sort in. A child's folder now begins with its
position among its parent's children, and placement finds an existing child by the path its parent
records rather than by recomputing a name. Proposal: [Folders in their order](../../../Proposals/FolderOrder.md),
step 1.

## What Changes
- A container held as a child is filed in `<NN> - <title>`, numbered by its position among its parent's distinct children and padded to two digits or as many as the count needs; a container at the top keeps its title alone.
- The walk's folder warning, and an edit's dry run, compare a folder with the name including its position.
- A placement, and the making of containers, take the folder a parent's sidecar records for a child, and name only the folders they make.
- Every scenario that spells out a child's folder is restated with its number.
