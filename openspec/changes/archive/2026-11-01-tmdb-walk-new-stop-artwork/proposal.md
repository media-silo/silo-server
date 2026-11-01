<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A new stop's artwork offered from TMDb

## Why
A new stop of a walk is to be created with any artwork TMDb offers for it, chosen to begin with, but
it was offered none: a held stop's artwork comes from reading it against TMDb, and a new stop is read
only as a draft, which kept no images. A missing season, or a film or series the library lacks, was
made with no poster, and its stop showed only its fields and references. Proposal: [A held tree
reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A draft from TMDb reads, with each container it reads from a record of its own, the images TMDb
  holds for the record, a season's through its series.
- A new stop offers each artwork kind TMDb has an image for, ticked to begin with, chosen from as a held
  stop's artwork is.
- Storing the walk puts a new stop's chosen artwork once the container is made, credited to its record.
