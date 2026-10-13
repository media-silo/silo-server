<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## RENAMED Requirements
- FROM: `### Requirement: Applying a ruleset to a binding makes a draft recipe for each output`
- TO: `### Requirement: Applying a ruleset to a binding makes a resolved recipe for each output`

## MODIFIED Requirements

### Requirement: Applying a ruleset to a binding makes a resolved recipe for each output
`POST /v1/bindings/{id}/recipes`, behind the operator's token, SHALL apply a ruleset to a binding:
it SHALL take an optional ruleset name — the binding's library's ruleset when left out — an optional
version — the latest when left out — and optionally the outputs to make, by profile, an object with
no profile naming the unqualified output, and every output when left out. It SHALL build the
binding's stack, as [rulesets](../rulesets/spec.md) describes, from the rules in force of its
lineage's containers as the index holds their sidecars at that moment and the ruleset applied;
resolve the binding once for each output it makes, deriving the facts for that output and resolving
the stack's rules against them; and store each recipe as `resolved`, naming its binding, its output and
its stack, and answer 201 with them. A ruleset or version the silo does not hold, an output the
ruleset does not make, or no ruleset named for a library that has none, SHALL be 400; a binding the
silo does not hold SHALL be 404. If a layer of the stack cannot be read — a version file that is not
there, or one the reader refuses — the application SHALL be refused with 422 naming whose rules they
are. If any output's resolution fails because a stream no rule decides, the application SHALL be
refused with 422 carrying the resolver's report. A refused application SHALL store nothing; the
binding stays, since the rules were incomplete and the binding was not wrong. Every recipe the
binding already has SHALL be left as it was, resolved or committed, so applying a newer version of the
ruleset, another ruleset, or the same one after a container's rules have moved to another version,
is the same operation again. `GET /v1/recipes/{id}` SHALL answer one recipe, with no token asked, or
404 for an id the silo does not know.

#### Scenario: two outputs, two recipes
- **WHEN** a ruleset whose outputs are an unqualified `mkv` and a `mobile` `mp4`, and whose video
  rules are one scaling to 720 lines when `profile` is `mobile`, then a condition-less copy, is
  applied to a binding
- **THEN** the binding has two resolved recipes, each naming that ruleset and version; the mobile one
  scales the video and the unqualified one copies it

#### Scenario: an output no rule can make
- **WHEN** a ruleset with a mobile output but no audio rule that holds when `profile` is `mobile` is
  applied to a binding
- **THEN** the application is refused with 422, naming the undecided audio stream; nothing is stored,
  and the binding stays

#### Scenario: the rules changed
- **WHEN** a binding's committed recipe was made by `household@3`, the ruleset is now at version 4,
  and `household` is applied to the binding again
- **THEN** a new recipe names `household@4`, and the committed recipe still names `household@3`

#### Scenario: another ruleset for the same binding
- **WHEN** a binding has a resolved recipe from `household`, and the operator applies `restoration` to it
- **THEN** the binding has a resolved recipe from each, and the first is as it was

#### Scenario: the library's standard
- **WHEN** a binding's library names `household` as its ruleset, at version 7, and an application to
  the binding names no ruleset
- **THEN** its recipes name `household@7`

#### Scenario: no ruleset anywhere
- **WHEN** a binding's library names no ruleset, and an application to the binding names none
- **THEN** the answer is 400, and nothing is stored

#### Scenario: a container's rules that cannot be read
- **WHEN** a container of a binding's lineage names a version of its rules that is not in its folder,
  and a ruleset is applied to the binding
- **THEN** the answer is 422 naming the container, and nothing is stored

Pinned by: `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`, `aBindingOrAnApplicationThatCannotBeMadeKeepsNothing`). `Tests/SiloTests/StackTests.swift` (`anApplicationResolvesThroughTheLineagesRulesInForce`, `aContainersRulesThatCannotBeReadRefuseTheApplication`, `anApplicationNamingNoRulesetTakesTheLibrarysStandard`). Applying a newer version of a ruleset to a binding that holds a committed recipe is pinned by nothing yet.

### Requirement: A recipe is committed once, and never changes after
Making a job from a resolved recipe SHALL commit it, and a committed recipe SHALL NOT change: neither
its decisions, its stack nor its ruleset version. `DELETE /v1/recipes/{id}`, behind the operator's
token, SHALL discard a resolved recipe and SHALL be 409 for a committed recipe.

#### Scenario: a resolved recipe discarded
- **WHEN** the operator discards a resolved recipe no job was made from
- **THEN** the recipe is gone, and its binding's other recipes are as they were

Pinned by: `Tests/SiloStoreTests/RecipeStoreTests.swift` (`aCommittedRecipeNeverChanges`, `aResolvedRecipeIsDiscardedAndTheRestStay`), `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`). Committing by making a job is pinned by `Tests/SiloTests/JobTests.swift` (`aJobGoesFromResolvedToPlaced`).

### Requirement: An application may name a branch of its ruleset
An application SHALL accept a `branch` of the ruleset it applies, and SHALL then resolve against
the branch's head, or the version it names when that version is on the branch. With no branch named
it SHALL resolve against the standard's head, or the version named. A branch the ruleset does not
have, or a version not on the branch named, SHALL be 400, and a closed branch SHALL be 409; each
stores nothing. A recipe SHALL need no field for its branch: its version is on exactly one.

#### Scenario: a trial branch applied to one binding
- **WHEN** `household`'s standard head is version 7, its branch `trial` holds version 8, and
  `household` is applied to a binding naming the branch `trial`
- **THEN** the recipes name `household@8`, and an application to another binding naming no branch
  makes recipes naming `household@7`

#### Scenario: a closed branch
- **WHEN** an application names a branch that has been promoted
- **THEN** the answer is 409, and nothing is stored

Pinned by: `Tests/SiloTests/BranchApplicationTests.swift` (`anApplicationOnABranchTakesItsHead`).
