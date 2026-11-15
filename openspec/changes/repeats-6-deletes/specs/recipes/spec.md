<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A recipe is committed once, and never changes after
Making a job from a resolved recipe SHALL commit it, and a committed recipe SHALL NOT change: neither
its decisions, its stack nor its ruleset version. `DELETE /v1/recipes/{id}`, behind the operator's
token, SHALL discard a resolved recipe and answer 204, SHALL be 409 for a committed recipe, and SHALL
be 404 for a recipe the silo does not hold, unless the silo discarded it, as its record of what it
deleted holds.

#### Scenario: a resolved recipe discarded
- **WHEN** the operator discards a resolved recipe no job was made from
- **THEN** the recipe is gone, and its binding's other recipes are as they were

#### Scenario: a discard sent again
- **WHEN** the operator discards a resolved recipe, and sends the same discard again
- **THEN** both answers are 204

Pinned by: `Tests/SiloStoreTests/RecipeStoreTests.swift` (`aCommittedRecipeNeverChanges`, `aResolvedRecipeIsDiscardedAndTheRestStay`), `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`). Committing by making a job is pinned by `Tests/SiloTests/JobTests.swift` (`aJobGoesFromResolvedToPlaced`). A discard sent again is pinned by nothing yet.
