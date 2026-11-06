<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# The console reads Wikidata for facts

## Why
Every fact the console takes from a provider is to come from Wikidata, whose statements are CC0. The
console needs a client for it: to search Wikidata's items, and to read a film, a collection, a series
with its seasons, a season with its episodes or its serials and their parts, and a serial with its
parts, each with its first date, its credits and the ids other providers give it. Proposal:
[Facts from Wikidata, content from TMDb](../../../Proposals/Wikidata.md), step 3.

## What Changes
- `WikidataClient`, behind `WikidataSource`, reads items' own statements through Wikidata's API and
  what points at an item, and who people are, through its query service. It needs no key, names
  SiloAdmin in its User-Agent, asks labels in the settings' language, and keeps to the service's
  limits.
- Its search finds films, series and collections, the most widely known first.
- Its reading orders a series' seasons, a season's members, a serial's parts and a collection's films
  as Wikidata numbers them, and tells a season's serials from its episodes, which Wikidata numbers with
  the same ordinal.
- Nothing is read into containers yet: drafting from Wikidata and the walk move to it together in the
  proposal's step 4, which the proposal now says.
