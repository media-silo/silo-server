<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A logo TMDb holds as an SVG, shown and put as TMDb's PNG of it

## Why
TMDb holds some logos as SVG images, and offers them among a record's logos as it offers any other.
The console showed each offered image from its path as TMDb gives it, and could not show an SVG: the
image stayed loading for as long as the stop was open, with nothing to say it never would. Storing a
walk that took one would put the SVG, which the silo refuses, since it takes artwork as a JPEG or a
PNG. TMDb also serves each such logo rendered as a PNG at the same path ending `.png`. Proposal: [A
held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A logo TMDb holds as an SVG is shown, and put when the walk is stored, as TMDb's PNG of it.
- An image TMDb does not give is shown as missing, rather than as loading.
