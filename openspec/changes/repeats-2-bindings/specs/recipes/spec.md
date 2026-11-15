<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

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
its stack, and answer 201 with them. For each output, a recipe the binding already holds, resolved or
committed, whose facts and recipe are the ones the application resolves — the same ruleset version,
stack, output and decisions — SHALL be answered in place of a new one, and no recipe stored for that
output; an application that makes no recipe SHALL be answered 200 with the recipes it found, storing
nothing, and one that makes any SHALL be answered 201 with every recipe it answers, made or found, so
that an application sent again is answered with the recipes the first made. A ruleset or version the silo does not hold, an output the
ruleset does not make, or no ruleset named for a library that has none, SHALL be 400; a binding the
silo does not hold SHALL be 404. If a layer of the stack cannot be read — a version file that is not
there, or one the reader refuses — the application SHALL be refused with 422 naming whose rules they
are. If any output's resolution fails because a stream no rule decides, the application SHALL be
refused with 422 carrying the resolver's report. A refused application SHALL store nothing; the
binding stays, since the rules were incomplete and the binding was not wrong. Every recipe the
binding already has SHALL be left as it was, resolved or committed, so applying a newer version of the
ruleset, another ruleset, or the same one after a container's rules have moved to another version,
is the same operation again, making recipes of what it now resolves. `GET /v1/recipes/{id}` SHALL answer one recipe, with no token asked, or
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

#### Scenario: an application sent again
- **WHEN** `household@3` is applied to a binding, and the same request is sent again
- **THEN** the first answer is 201 with a recipe for each output and the second 200 with the same
  recipes, and the binding holds one recipe for each output

#### Scenario: an application after its recipe was committed
- **WHEN** `household@3` is applied to a binding, a job is made from the unqualified output's recipe,
  and `household@3` is applied again
- **THEN** the answer names the committed recipe for the unqualified output, and no recipe is stored
  for it

#### Scenario: one output held, another not
- **WHEN** the unqualified output of `household@3` is applied to a binding, and then every output of
  it, the unqualified and `mobile`
- **THEN** the second answer is 201 with the unqualified recipe made first and a new `mobile` recipe,
  and one recipe is stored

Pinned by: `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`, `aBindingOrAnApplicationThatCannotBeMadeKeepsNothing`). `Tests/SiloTests/StackTests.swift` (`anApplicationResolvesThroughTheLineagesRulesInForce`, `aContainersRulesThatCannotBeReadRefuseTheApplication`, `anApplicationNamingNoRulesetTakesTheLibrarysStandard`). Applying a newer version of a ruleset to a binding that holds a committed recipe is pinned by nothing yet, and so is an application answered with the recipes the binding holds.
