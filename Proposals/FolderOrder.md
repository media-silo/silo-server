<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0016-folder-order

Modified: 2026-10-21

# Folders in their order

This proposes that a library's folders list in the order their containers have, and stay named as
their containers are. A container held as a child gets a folder whose name begins with its position
among its parent's children: `Doctor Who (1963)/13 - Season 13/03 - Pyramids of Mars/`. A container at
the top of a library keeps its title alone. When an edit changes a container's title, or the order or
number of a parent's children, the silo renames the folders it changes, records their new paths in the
sidecars that name them, and re-reads what moved. A library changed by hand is brought into line by an
operator's request to lay it out again.

It rests on [0015-presentation-identity](PresentationIdentity.md). A presentation's id no longer
depends on its path, so a folder can move without a player, a job or the media route losing a
presentation beneath it. That removes the reason for 0012's fourth principle, that paths are made and
never maintained, and this proposal replaces it.

It follows smddb's own layout ([smddb#40](https://github.com/project-smd/smddb/pull/40)), which numbers
a child's folder the same way and moves folders when a container's title or order changes.

## The problem

**A library lists in the wrong order.** A season's serials sort by title: *Planet of Evil* before
*Pyramids of Mars* before *Terror of the Zygons*, the reverse of broadcast. A series' seasons sort as
text, so Season 10 comes before Season 2. An operator looking at a library on disk, or at the paths
the console's dry runs show, sees the structure scrambled. The order is already known: it is the order
the parent's document gives its children.

**Folders drift from their containers, and nothing brings them back.** 0012 renames nothing on an edit,
so a corrected title leaves its folder as it was, and the walk warns of it from then on. The reason was
that a move changed the ids of the presentations beneath it. After 0015 it changes none, and the
warning is reporting something the silo could simply fix.

**Placement names folders from what the producer sends.** A placement works out every folder of its
lineage from the containers it was handed. When that disagrees with the library, it makes a second
folder for a container the library holds, and the walk reports the container held twice.

## Principles

0012's principles one to three stand. Its fourth, that paths are made and not maintained, is replaced
by the first here.

1. **A folder follows its container.** A folder's name is what the layout gives its container now: its
   position among its parent's children and its title. The silo keeps it so when it changes either,
   and a change made by hand is reported until the library is laid out again.
2. **What is on disk is followed, not recomputed.** A container already in a library is where its
   parent's sidecar says it is. Placement and the making of containers find it there, and name only a
   folder they make.
3. **A move is the folder, not the media.** Renaming a folder moves everything in it at once and
   changes no presentation's file name within it. A presentation's own file keeps its name.

## What changes

**A child's folder begins with its position.** The folder of a container held as a child is named
`<NN> - <title>`: its position among its parent's distinct children, counted from one in the order the
parent's sequences and then its extras name them, padded with zeros to two digits or to as many as the
parent's count of children needs. The title part is sanitised as before. A container at the top of a
library, which nothing orders, is named for its title alone. The id is not part of the name, as it is
in smddb: a library folder holds one `container.smd`, and the sidecar names its container.

**An edit moves what it renames.** When an applied edit of a container's own fields changes its display
title, the silo renames its folder. When it changes the order or the set of the container's children,
the silo renames the folders of each held child whose position changed. Each new path is recorded in
the sidecar that names the child, which is the one library fact an edit now changes, and each moved
container is re-read into the index, with the containers beneath it. The edit's result lists the moves,
`from` and `to`, and a dry run lists the moves it would make. A rename that fails, as one can on a
network share holding the folder open, leaves that folder where it is and is reported as a warning; the
edit is still applied, and the walk goes on warning of the folder until it is laid out again.

**The making of containers numbers in place.** 0013 makes a child beneath a parent the library holds,
after the parent's edit names it. That edit has already renumbered the siblings, so the new folder is
made at its position among them.

**A library is laid out again on request.** `POST /v1/libraries/{library}/layout`, with `dryRun`,
renames every container folder in the library whose name is not the one the layout gives it, top down,
records each new path in its parent's sidecar, and re-reads the library. The answer lists the moves and
any that failed. It is the operator's, for a library whose folders were renamed or moved by hand.

**The walk's folder warning includes the position.** The walk warns of a folder whose name is not the
one the layout would give the container now, including its position, in the words it uses today. After
this proposal only a change made outside the silo or a failed rename leaves such a folder.

**Placement follows the path its parent records.** For each container of its lineage below the top, a
placement takes the folder its parent's sidecar records for it, when there is one, and names only a
folder for a container its parent does not record. The making of containers does the same, since it
shares the placer's naming. A placement whose lineage gives a container a title the library has since
corrected files into the container's folder rather than beside it, which removes the condition 0013
noted.

**The console lays a library out.** A library's detail gains **Lay Out Again…**, which shows the dry
run's moves and applies them. A container's edit review shows the moves its store would make.

## What this looks like to the operator

The operator imports Season 13 of *Doctor Who* from smddb. The dry run says it will write
`Doctor Who (1963)/13 - Season 13/container.smd` and `Doctor Who (1963)/13 - Season 13/01 - Terror of
the Zygons/container.smd`, and so on to `06 - The Seeds of Doom`, and on disk the season lists its
serials in broadcast order. Later they correct the series' title in the console, and the review says
the series' folder moves from `Doctor Who (1963)` to `Doctor Who (1963–1989)`; they store it, and the
player goes on resuming *Pyramids of Mars* where it stopped. Someone renames a season's folder by hand on the share; the walk warns of it until they choose **Lay
Out Again…** and apply its move.

## What this asks of an implementation

Three steps, one pull request each, each carrying its change in
[`openspec/changes/`](../openspec/changes/). 0015 is built first.

### 1. Numbered folders, followed by placement

`LibraryLayout` names a child's folder from its position; the placer and the maker take a recorded child
path where the parent has one; the walk, the incremental scan and an edit's dry run compare a folder with
the name including its position. Every scenario that spells out a child's folder changes with it.
`folder-order-1-numbered`.

Tests: a series, a season and a serial placed into an empty library make `01 - Season 13/01 - Pyramids of
Mars`; a placement after a container's title was corrected in the library files into its folder; a
library with an unnumbered child folder is walked with the warning and placed into without a second
folder; a parent with a hundred children pads to three digits.

### 2. Edits move folders, and a library is laid out again

The edit renames and renumbers what it changes and lists the moves; the layout route.
`folder-order-2-moves`.

Tests: a title edit renames the folder and the presentations beneath keep their ids; inserting a season
before Season 13 renumbers Season 13's folder and the series' sidecar records its new path; a dry run
lists the moves and moves nothing; laying out a library with unnumbered folders numbers them, records
their paths and leaves every id as it was.

### 3. The console

The edit review's moves and **Lay Out Again…**. `folder-order-3-console`.

## Non-goals

- **Renaming presentation files.** A presentation's file is named for its item and display name when it
  is placed, and an edit of an item's title renames nothing. Whether files follow their items as folders
  follow their containers is a question about what players show, for later.
- **Renumbering on its own.** The silo moves folders when it changes what they are named from, and when
  asked to lay a library out. It does not watch for changes made by hand.
- **The id in the folder name.** smddb's folders carry it because nothing else in a folder of the data
  repository says which container it is. A library's sidecar does.

## Open questions

1. **Numbering the top of a library.** A library of films lists by title, which is right. A library whose
   roots are a collection's members might want their order. Roots have no parent to give them one, and a
   collection that wants an order holds its members as children.
2. **A move under a stream.** Renaming a folder leaves an open file readable on a local disk, so a stream
   in progress continues. A network share may refuse the rename while the file is open, which this
   proposal reports and leaves for the next layout. Whether to retry by itself is for when it happens.
