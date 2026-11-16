<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Bindings

## Purpose

A binding says what one entry of a library is made from: segments of one or more sources, each a
whole source or a span of its chapters, joined in order, with the entry and its feature map. It is
checked whole before it is kept and never changed once made. It names no ruleset: a binding is a
fact about the library, and applying a ruleset to it is a separate act, made as often as the rules
change, which makes a resolved recipe for each output. This spec covers the bindings routes, the binding
and the joining of its segments in `Sources/SiloKit`, `BindingService` and `BindingStore`; applying a
ruleset to a binding is [recipes](../recipes/spec.md)'s.

Rationale: [Ingestion proposal — Bindings](../../../Proposals/Ingestion.md) — each thing is said once:
an entry is bound once, however many outputs are made of it.
Documentation: [README](../../../README.md).

## Requirements

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

Pinned by: `Tests/SiloKitTests/BindingTests.swift` (`anEpisodeOutOfAPlayAllTitleIsItsChapterSpan`, `aFilmAcrossTwoDiscsIsBothWhole`), `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`), `Tests/SiloStoreTests/RecipeStoreTests.swift` (`bindingsAndRecipesSurviveARestart`), `Tests/SiloTests/RepeatTests.swift` (`aBindingSentAgainIsTheBindingThereIs`).

### Requirement: A binding's segments are joined in order, and must share a stream layout
A binding's media SHALL be its segments' spans joined end to end in order, the way `ffmpeg`'s concat
demuxer presents them, so that a stream's index means the same in every segment and in the joined
media. A segment's span SHALL run from the start of its `from` chapter to the start of the chapter
after its `to`, or to the source's end; a segment without a span is its whole source. The segments'
input specs SHALL describe the same streams — the same kinds and codecs at the same indices — and a
binding whose segments do not SHALL be refused, naming the first stream that differs.

#### Scenario: two sources that cannot be joined
- **WHEN** a binding's first segment has an AC-3 stream at index 1 and its second a DTS stream there
- **THEN** the binding is refused, naming stream 1

Pinned by: `Tests/SiloKitTests/BindingTests.swift` (`anEpisodeOutOfAPlayAllTitleIsItsChapterSpan`, `aFilmAcrossTwoDiscsIsBothWhole`, `segmentsThatCannotBeJoinedAreRefused`).

### Requirement: A binding that cannot be made is refused whole
A binding SHALL be refused with 400, naming why, and nothing stored, when its library is unknown to
the silo; a container document cannot be read; the item is not in the last container; the
alternative is not one of that container's; the feature map names a feature the container does not
have, or a stream the joined media does not have; a segment names a source the silo does not have; a
span names a chapter its source does not have, or its `to` comes before its `from`; the segments
cannot be joined.

#### Scenario: a span past the end
- **WHEN** a binding's segment spans chapters 3 to 5 of a source with four chapters
- **THEN** the binding is refused with 400, naming chapter 5, and nothing is stored

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aBindingOrAnApplicationThatCannotBeMadeKeepsNothing`), `Tests/SiloKitTests/BindingTests.swift` (`segmentsThatCannotBeJoinedAreRefused`).

### Requirement: Bindings are read openly
`GET /v1/bindings/{id}` SHALL answer the binding with the ids of its recipes, or 404 for an id the
silo does not know, with no token asked.

#### Scenario: a binding and its recipes
- **WHEN** a client reads a binding to which a ruleset of two outputs has been applied
- **THEN** the answer carries the binding and the ids of its two recipes

Pinned by: `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`).

### Requirement: A binding's rules are versioned and set by their own route
`PUT /v1/bindings/{id}/rules`, behind the operator's token, SHALL take a rules document, read it as a
binding's rules are read, and store it as the binding's next version, from 1, making it the version in
force; a document the reader refuses SHALL be 400 with its refusal, and a binding the silo does not
hold 404. A document whose bytes are those of the version in force SHALL store nothing, and be answered
200 as that version, so that rules put again are answered as the first put was. `GET /v1/bindings/{id}/rules` SHALL answer, with no token asked, the version in force with
its document and the numbers of every version. Until the binding's first presentation is placed, its
versions SHALL be kept in the silo's state directory; from then on they SHALL be kept in the library,
in the folder `rules/bindings/<binding id>` beside the sidecar of the container holding the binding's
item, a new version written there — its file first, then the item's `<rules>` moved to it — and the
silo's copy no longer kept. A version SHALL NOT be rewritten, wherever it is kept. Storing a binding's
rules SHALL change no recipe: a recipe that should carry them is resolved by applying the rules again.

#### Scenario: a decision before anything is placed
- **WHEN** a producer stores rules copying audio 1 for a binding none of whose files has been placed
- **THEN** the answer names version 1, the version is in the silo's state directory and not in the
  library, and applying a ruleset to the binding then makes recipes whose audio 1 is copied by the
  binding's rule

#### Scenario: a later decision, once placed
- **WHEN** a binding whose file has been placed has its rules stored again
- **THEN** version 2's file is written in the library's `rules/bindings/<binding id>` folder, and the
  item's `<rules>` for the binding names version 2

#### Scenario: rules put again
- **WHEN** a binding's rules are put as version 1, and the same document is put again
- **THEN** the second answer names version 1, and the binding has one version

#### Scenario: rules put back
- **WHEN** a binding's rules are put as version 1, another document as version 2, and the first
  document again
- **THEN** the third answer names version 3, in force, whose document is version 1's

Pinned by: `Tests/SiloTests/BindingRulesTests.swift` (`rulesStoredBeforePlacementMoveIntoTheLibraryWithTheFirstFile`, `rulesPutAgainAreTheVersionInForce`), `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`, for the routes).
