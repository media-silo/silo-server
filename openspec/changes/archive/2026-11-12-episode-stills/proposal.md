<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# An episode's stills are offered for its thumb

## Why
A walk offered a film, a series, a collection or a season TMDb's posters, backdrops and logos, and an
episode nothing, though the library takes a `thumb` and TMDb gives nearly every episode a still. An
episode's stop had its own fields but no artwork.

## What Changes
- TMDb's season answer, which a season's episodes' overviews are already read from, is read for each
  episode's number and the still the season gives it; TMDb's other stills of the episode are read
  beneath its season and series by their numbers, the season's still first.
- A drafted episode's new stop offers the stills for its `thumb`, ticked to begin with unless this Mac's
  settings leave it unticked, and storing the walk puts the one chosen on the episode once it is made,
  credited to the episode's TMDb id.
- A held episode whose folder has no thumb is offered the stills at its stop, read through its season and
  the series above it, as its outline is.
- Drafting a season asks TMDb once more for each of its episodes that TMDb lists.

## Impact
- Modified: a stop's artwork chosen from TMDb's images; a new stop's artwork read with its draft.
