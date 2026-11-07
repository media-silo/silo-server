<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# The walk from both

## Why
The console took every fact it drafted and walked from TMDb, whose terms do not let its data be kept
or shared as facts. Wikidata's statements are CC0, and the client that reads them is in place. So
drafts and the walk now take their facts, structure and ids from Wikidata, and only content, an
outline and artwork, from TMDb, read through the TMDb ids Wikidata holds. They move together, so the
walk's start is reworked once. Proposal:
[Facts from Wikidata, content from TMDb](../../../Proposals/Wikidata.md), step 4.

## What Changes
- The console searches Wikidata, and drafts a film, a series, a season or a collection from
  Wikidata's item through the create route: its title, year and ids are Wikidata's, a season holds
  the serials Wikidata lists as containers beneath it, and its outline and artwork are TMDb's,
  attributed. An item smddb holds is imported instead, and one the library holds is walked.
- A held container is read against its Wikidata item, or through the nearest container above it that
  carries one, or through the Wikidata ids its entries carry. An entry matches an episode by
  Wikidata's id or by any other id Wikidata holds for it, and is offered the ids it lacks. A season
  carrying no Wikidata id is suggested by its title or its number.
- A series' specials are the episodes Wikidata files beneath it in none of its seasons, in the order
  they aired, and go into the pool. TMDb's season 0 is no longer read.
- TMDb's episode groups, its runtimes and its lookup by external id are no longer read. A special is
  suggested as a duplicate of the item a library holds that carries one of the special's other ids.
- An outline or an image kept longer than TMDb's terms allow is offered to be read again, or, when
  TMDb no longer has one, to be removed with its attribution.
- With no TMDb token, a draft holds every fact and no content, and a walk reviews every fact and says
  why it read no content.
- A walk kept from TMDb's readings is not read: the console keeps walks in a new file, and a container
  is walked again.
