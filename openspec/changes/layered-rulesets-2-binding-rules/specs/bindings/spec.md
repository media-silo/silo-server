<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A binding's rules are versioned and set by their own route
`PUT /v1/bindings/{id}/rules`, behind the operator's token, SHALL take a rules document, read it as a
binding's rules are read, and store it as the binding's next version, from 1, making it the version in
force; a document the reader refuses SHALL be 400 with its refusal, and a binding the silo does not
hold 404. `GET /v1/bindings/{id}/rules` SHALL answer, with no token asked, the version in force with
its document and the numbers of every version. Until the binding's first presentation is placed, its
versions SHALL be kept in the silo's state directory; from then on they SHALL be kept in the library,
in the folder `rules/bindings/<binding id>` beside the sidecar of the container holding the binding's
item, a new version written there — its file first, then the item's `<rules>` moved to it — and the
silo's copy no longer kept. A version SHALL NOT be rewritten, wherever it is kept. Storing a binding's
rules SHALL change no recipe: a draft that should carry them is made by applying the rules again.

#### Scenario: a decision before anything is placed
- **WHEN** a producer stores rules copying audio 1 for a binding none of whose files has been placed
- **THEN** the answer names version 1, the version is in the silo's state directory and not in the
  library, and applying a ruleset to the binding then makes drafts whose audio 1 is copied by the
  binding's rule

#### Scenario: a later decision, once placed
- **WHEN** a binding whose file has been placed has its rules stored again
- **THEN** version 2's file is written in the library's `rules/bindings/<binding id>` folder, and the
  item's `<rules>` for the binding names version 2

Pinned by: nothing yet.
