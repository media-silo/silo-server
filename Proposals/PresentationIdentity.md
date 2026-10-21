<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0015-presentation-identity

Modified: 2026-10-21

# A presentation is named for what it is

This proposes that a presentation's id be derived from what the presentation is — its library, its
container, its item, its alternative and its profile — rather than from where its file sits. Today the
id is the hash of the library and the file's path, so any move of a file or of a folder above it gives
the presentation a new id, and everything that held the old one loses it: a player's resume point, a
job's record of what it placed, the out-of-date report's account of it, a link to the media route. With
the id taken from what the presentation is, a file can move and keep its id, and the media route finds
it at its new path.

The change is small in code and large in what it allows. 0012 decided that paths are made and not
maintained, because a move in a library changes ids that clients hold. With this proposal a move
changes no id, and [0016](#what-comes-next) can keep a library's folders named and numbered as its
containers are, rather than only warning when they drift.

## The problem

**An id is where a file is, not what it is.** `IndexedPresentation.id(library:path:)` hashes the
library and the path of the presentation's file. The id is stable across rescans, which is all it was
asked to be. Moving the file changes it, and so does renaming any folder above the file.

**Everything that holds an id loses it on a move.** A silo does not record what has been watched, so a
player keeps resume points and watched state by presentation id. A job records the id of the
presentation it placed, and the checks compare those with the index to report presentations placed
without a job and to describe out-of-date ones. The trial view links the placed file by its id. After
a move, the media route answers 404 for the old id for good, the job's id names nothing, the
presentation is counted as placed without a job although one placed it, and the out-of-date report
loses its file, item and profile.

**So nothing may move.** 0012's fourth principle follows from this, and so does the walk's warning for
a folder not named as the layout would name it: the folder cannot be renamed, so it is reported. Every
proposal that would keep a library tidy — renumbering folders, renaming one whose title was corrected,
laying a library out again — runs into it.

**What a presentation is, is already unique.** Within one library's sidecar for a container, the
validator refuses two presentations of one item with the same alternative and profile, and an item's
id is unique across the container's sequences and extras. A library holds a container once. So the
library, the container, the item, the alternative and the profile already name one presentation
wherever the validator has been asked: at placement, at the making of containers and at an edit.

## Principles

1. **An id names what a presentation is.** Two presentations are the same when they are the same
   item of the same container in the same library, in the same alternative and profile. Where the
   file is, is a fact about it that can change.
2. **What the walk indexes is unique.** The walk does not trust a sidecar to have been validated. Two
   presentations that would share an id are an error it reports, and it indexes the first, as it does
   for a container held twice in a library.

## What changes

**The id.** A presentation's id is the 64-bit FNV-1a hash, written as sixteen lowercase hexadecimal
characters as now, of its library's id, its container's id, its item's id, its alternative and its
profile, joined by `|`, with an absent alternative or profile written as nothing. An unqualified
presentation of the default alternative is the presentation with no alternative, whatever the default
is, so changing which alternative is the default changes no id. Nothing else changes what an id is
formed from: not its file, its display name, its tracks, its chapters, its source or its transform.

**What changes an id.** Only a change to what the presentation is. A presentation placed again with
another profile is another presentation. An item cannot be renamed while it has presentations, since
an edit refuses to take away an item a presentation names, and a container's id is never reissued.
Changing a library's id would change every id in it, which nothing does.

**The walk refuses what would share an id.** A presentation whose id another in the same sidecar
already has — the same item, alternative and profile, which only a hand edit makes — is reported as an
error, in the validator's words, `item <id> has two presentations for the same alternative and
profile`, and is not indexed. Two presentations that name one file are reported the same way,
`item <id>: "<file>" is named by another presentation`, and the second is not indexed. Today the second
of those makes the index's insert fail and stops the walk.

**A moved file is found again.** The media route already re-reads a container's sidecar when it finds
a presentation's file missing. When the sidecar now records the presentation at another file — moved
by hand and the sidecar edited, or moved by the silo — the id is the same, and the route serves the file
from its new path instead of answering 404.

**Nothing is migrated.** No silo yet holds a container or a presentation, so no index, job record or
player holds an id in the old form. The change is made now, before any does, and the new form is the
only one there has been.

## What this looks like to the operator

Nothing, until something moves. The operator renames the folder of a film by hand, edits nothing else,
and the next walk reads the sidecar at its new path: the film's presentations have the ids they had,
the player resumes where it stopped, and the job that placed the film still names its presentation, so
the film is not reported as placed without a job. When 0016 renumbers a season's folders after a
season is inserted before it, the same is true of every episode in them.

## What this asks of an implementation

One step, one pull request, carrying the change in
[`openspec/changes/presentation-identity`](../openspec/changes/presentation-identity).

`IndexedPresentation.id` takes the library, container, item, alternative and profile; the walk reports
and skips a presentation sharing an id or a file with another in its sidecar; the media route serves a
file found again by a refresh; and every caller of the id — the index entry, the placement route, the
job service — passes what the presentation is.

Tests: a presentation's id is the same after its container's folder is renamed and the library walked
again; the media route serves a presentation by its old id after its file was moved and its sidecar
edited; two presentations of one shape in a sidecar index the first and report the second, and so do
two naming one file; a job's placed presentation keeps its id after its folder is renamed, so it is not
reported as placed without a job.

## What comes next

**0016, folders in their order,** rebuilt on this: a child's folder numbered by its position, and kept
numbered and named as its container is, the silo moving folders when an edit or a making changes a
title or an order.

## Non-goals

- **Moving files.** This proposal moves nothing; it makes moving safe.
- **A migration.** No silo holds a presentation yet, so there is no id in the old form to carry over.
- **Ids that survive a container being re-keyed,** which nothing does. smddb's provisional ids, if a
  service ever declines one, would need it, and that is 0013's first open question.

## Open questions

1. **Whether the library belongs in the id.** One container's presentations in two libraries are two
   presentations — two files, often two encodings — and a player browsing both must tell them apart, so
   the library is in. A player that wanted one resume point across a film's 1080p and 4K libraries
   would want ids without it, and could get that from the container and item instead.
