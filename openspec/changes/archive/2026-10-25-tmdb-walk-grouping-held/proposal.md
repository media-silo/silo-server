<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Grouping what a held container lacks

## Why
A held season the operator has said is one of TMDb's offered its missing episodes one by one, while a
drafted season's could be grouped into the serials TMDb's titles suggest. Grouping assumed every group
was a serial, which holds for Doctor Who and not for every series. And a special was marked as
suggested for the open container on its air date alone, marking many that had nothing to do with it.
Proposal: [A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A held container's missing episodes are grouped as a draft's entries are, each group made as a new
  container beneath it when the walk is stored, named where its first episode would have gone.
- No kind of group is assumed: the kind the container's groups mostly are is chosen to begin with, and
  otherwise the operator chooses one.
- A special is marked as suggested here only when its title names the container, an entry of it, a
  story an entry is part of, or a container beneath it, or smddb files it there.
- Once the operator says which season a held one is, the series' children show it as held by it, and a
  season it was only suggested to be is missing again, without reading the series again.
