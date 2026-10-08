<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## REMOVED Requirements

### Requirement: An adjustment replaces a draft's decision and is recorded with what it replaced
**Reason**: A person's decision about one entry is now a rule in the binding's own rules, the nearest
layer, so it is kept, versioned and made again whenever the rules are applied; an adjustment lived on
one draft and was lost on the next application. A draft is what its stack decided, and nothing is
patched onto it.
**Migration**: Store the decision as the binding's rules with `PUT /v1/bindings/{id}/rules`, as
[bindings](../bindings/spec.md) describes — a stream named by `audio.index` or `subtitle.index` — and
apply the rules to the binding again. `PUT /v1/recipes/{id}/adjustments` is removed, and a recipe
keeps no `adjustments` and no separate `resolved` decisions.

## MODIFIED Requirements

### Requirement: A recipe is committed once, and never changes after
Making a job from a draft recipe SHALL commit it, and a committed recipe SHALL NOT change: neither
its decisions, its stack nor its ruleset version. `DELETE /v1/recipes/{id}`, behind the operator's
token, SHALL discard a draft and SHALL be 409 for a committed recipe.

#### Scenario: a draft discarded
- **WHEN** the operator discards a draft no job was made from
- **THEN** the recipe is gone, and its binding's other recipes are as they were

Pinned by: `Tests/SiloStoreTests/RecipeStoreTests.swift` (`aCommittedRecipeNeverChanges`, `aDraftIsDiscardedAndTheRestStay`), `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`). Committing by making a job is pinned by `Tests/SiloTests/JobTests.swift` (`aJobGoesFromADraftToPlaced`).
