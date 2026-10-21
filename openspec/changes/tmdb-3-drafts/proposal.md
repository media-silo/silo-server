<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Drafting containers from TMDb

## Why
A container smddb lacks is typed into the console by hand, item by item, though nearly all of it is
already at TMDb. The console reads TMDb's record as a draft the operator shapes before creating it.
It takes only facts plainly, attributes the outline, and leaves attributed fields out of what it
proposes to smddb. Proposal: [TMDb in the console](../../../Proposals/Tmdb.md).

## What Changes
- SiloAdmin's settings take a TMDb read access token, kept in this Mac's keychain, and a language,
  and the console credits TMDb wherever it shows what it read there.
- A movie, series, season, collection or episode group from TMDb is read as a tree of new-container
  drafts with provisional ids, shaped in the form and created through the create route with its
  attributions.
- A record smddb holds is imported from smddb rather than drafted, and one the library holds is not
  drafted.
- The form shows an attributed outline with its attribution and keeps it through an edit.
- A contribution to smddb takes smddb's value, or none, for each attributed field, and says which it
  left out.
