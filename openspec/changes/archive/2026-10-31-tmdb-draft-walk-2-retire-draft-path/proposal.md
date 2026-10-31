<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# The one-shot draft from TMDb retired for its walk

## Why
Once a record the library lacks was walked from a draft of it, the console's one-shot path for a
draft, kept in a store of its own, checked as a dry run and made in one request, was no longer reached
from the app. Proposal: [A held tree reviewed against TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A walk from a draft takes the draft's new breakouts as companion series, and its drafted
  alternatives as the walk's.
- A creation the silo refuses stops the walk's store and is kept to be stored again.
