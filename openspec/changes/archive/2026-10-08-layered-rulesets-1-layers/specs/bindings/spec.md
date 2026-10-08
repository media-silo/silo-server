<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A binding says what one entry is made from, segment by segment
`POST /v1/bindings`, behind the operator's token, SHALL take a binding: the library, the item's
container lineage as repository documents, the item, and its optional alternative; the feature map,
mapping the last container's features to streams by kind and index from one among streams of the
kind; the chapter names the presentation will carry; and one or more segments, each a source's id and optionally a span of its chapters,
`from` and `to` inclusive. A binding SHALL name no ruleset: applying one is its own operation, as
[recipes](../recipes/spec.md) describes, and making a binding SHALL resolve nothing. The silo SHALL
mint the binding's id, a lowercased UUID that is also the binding's id in the shared store should it
be contributed, keep the binding as one JSON file under its state directory, and never change
a binding once made. What the sidecar records of where a presentation came from is derived
from the binding — its id and its segments' sources' natural keys — and never given beside it.

#### Scenario: an episode out of a play-all title
- **WHEN** the operator binds part two of a serial to chapter 2 of a source whose chapters are its
  four episodes
- **THEN** the binding is made with one segment, that source spanning chapters 2 to 2

#### Scenario: a film across two discs
- **WHEN** the operator binds a film to two sources, each a whole disc title with the same streams
- **THEN** the binding is made with two segments, in that order

Pinned by: `Tests/SiloKitTests/BindingTests.swift` (`anEpisodeOutOfAPlayAllTitleIsItsChapterSpan`, `aFilmAcrossTwoDiscsIsBothWhole`), `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`), `Tests/SiloStoreTests/RecipeStoreTests.swift` (`bindingsAndRecipesSurviveARestart`).
