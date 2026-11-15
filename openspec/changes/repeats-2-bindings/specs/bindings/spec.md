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
be contributed, keep the binding as one JSON file under its state directory, answer 201 with it, and
never change a binding once made. A binding that says what a binding the silo holds says — its
library; its item, as the id of the item's container and the item's id; its alternative; its segments,
in order, each a source and a span; its feature map; and its chapter names — SHALL be that binding,
answered 200 with nothing stored, whatever copies of its lineage's documents it carries, since the
silo reads the lineage from the library whenever it resolves or checks the binding. What the sidecar
records of where a presentation came from is derived from the binding — its id and its segments'
sources' natural keys — and never given beside it.

#### Scenario: an episode out of a play-all title
- **WHEN** the operator binds part two of a serial to chapter 2 of a source whose chapters are its
  four episodes
- **THEN** the binding is made with one segment, that source spanning chapters 2 to 2

#### Scenario: a film across two discs
- **WHEN** the operator binds a film to two sources, each a whole disc title with the same streams
- **THEN** the binding is made with two segments, in that order

#### Scenario: a binding sent again
- **WHEN** a binding is made, and the same request is sent again
- **THEN** the first answer is 201 and the second 200 with the same binding, and the silo holds one
  binding of the entry

#### Scenario: another span of the same source
- **WHEN** part two of a serial is bound to chapter 2 of a source, and part three to chapter 3 of it
- **THEN** each is a binding of its own

#### Scenario: a binding sent with a newer copy of its container
- **WHEN** a binding is made, its container's document is edited in the library, and the binding is
  sent again carrying the edited document
- **THEN** the answer is 200 with the binding made first, and the silo holds one binding of the entry

Pinned by: `Tests/SiloKitTests/BindingTests.swift` (`anEpisodeOutOfAPlayAllTitleIsItsChapterSpan`, `aFilmAcrossTwoDiscsIsBothWhole`), `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`), `Tests/SiloStoreTests/RecipeStoreTests.swift` (`bindingsAndRecipesSurviveARestart`). A binding recognised by what it says is pinned by nothing yet.
