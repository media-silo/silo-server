<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Applying a ruleset to a binding makes a draft recipe for each output
`POST /v1/bindings/{id}/recipes`, behind the operator's token, SHALL apply a ruleset to a binding:
it SHALL take an optional ruleset name — the binding's library's ruleset when left out — an optional
version — the latest when left out — and optionally the outputs to make, by profile, an object with
no profile naming the unqualified output, and every output when left out. It SHALL build the
binding's stack, as [rulesets](../rulesets/spec.md) describes, from the `<rules>` of its lineage's
containers as the index holds their sidecars at that moment and the ruleset applied; resolve the
binding once for each output it makes, deriving the facts for that output and resolving the stack's
rules against them; and store each recipe as a `draft`, naming its binding, its output, the ruleset
version resolved and its container layers, and answer 201 with them. A ruleset or version the silo
does not hold, an output the ruleset does not make, or no ruleset named for a library that has none,
SHALL be 400; a binding the silo does not hold SHALL be 404. If a container of the lineage has
`<rules>` the reader refuses, the application SHALL be refused with 422 naming the container. If any
output's resolution fails because a stream no rule decides, the application SHALL be refused with
422 carrying the resolver's report. A refused application SHALL store nothing; the binding stays,
since the rules were incomplete and the binding was not wrong. Every recipe the binding already has
SHALL be left as it was, draft or committed, so applying a newer version of the ruleset, another
ruleset, or the same one after a container's rules have changed, is the same operation again.
`GET /v1/recipes/{id}` SHALL answer one recipe, with no token asked, or 404 for an id the silo does
not know.

#### Scenario: two outputs, two recipes
- **WHEN** a ruleset whose outputs are an unqualified `mkv` and a `mobile` `mp4`, and whose video
  rules are one scaling to 720 lines when `profile` is `mobile`, then a condition-less copy, is
  applied to a binding
- **THEN** the binding has two draft recipes, each naming that ruleset and version; the mobile one
  scales the video and the unqualified one copies it

#### Scenario: an output no rule can make
- **WHEN** a ruleset with a mobile output but no audio rule that holds when `profile` is `mobile` is
  applied to a binding
- **THEN** the application is refused with 422, naming the undecided audio stream; nothing is stored,
  and the binding stays

#### Scenario: the rules changed
- **WHEN** a binding's committed recipe was made by `household@3`, the ruleset is now at version 4,
  and `household` is applied to the binding again
- **THEN** a new draft names `household@4`, and the committed recipe still names `household@3`

#### Scenario: another ruleset for the same binding
- **WHEN** a binding has a draft from `household`, and the operator applies `restoration` to it
- **THEN** the binding has a draft from each, and the first is as it was

#### Scenario: the library's standard
- **WHEN** a binding's library names `household` as its ruleset, at version 7, and an application to
  the binding names no ruleset
- **THEN** its drafts name `household@7`

#### Scenario: no ruleset anywhere
- **WHEN** a binding's library names no ruleset, and an application to the binding names none
- **THEN** the answer is 400, and nothing is stored

#### Scenario: a container's rules that cannot be read
- **WHEN** a container of a binding's lineage has `<rules>` testing a fact no rule can test, and a
  ruleset is applied to the binding
- **THEN** the answer is 422 naming the container, and nothing is stored

Pinned by: `Tests/SiloTests/ServerTests.swift` (`entriesAreBoundAndRulesetsAppliedToThem`, `aBindingOrAnApplicationThatCannotBeMadeKeepsNothing`). Applying a newer version of a ruleset to a binding that holds a committed recipe, the library's standard, and container rules are pinned by nothing yet.

## ADDED Requirements

### Requirement: A decision names the layer its rule came from
Each decision in a recipe SHALL name, beside its rule, the layer the rule came from: the ruleset
applied as `name@version`, or a container's rules by the container's id. The rule SHALL be named
within its layer — its `id`, or `#n` for its position among that layer's rules. An adjustment SHALL
leave a decision's layer as it was, as it leaves its rule.

#### Scenario: two layers decide one entry
- **WHEN** an entry's video is decided by the unnamed first rule of a container's rules and its audio
  by the rule `lossless-main` of `household@7`
- **THEN** the video's decision names rule `#1` of the layer named by the container's id, and the
  audio's names rule `lossless-main` of layer `household@7`

Pinned by: nothing yet.

### Requirement: A recipe records the container layers it was resolved against
A recipe SHALL record its stack's container layers, nearest first, each as the container's id and
the SHA-256 digest of its `<rules>` element's canonical form. The silo SHALL keep each container
layer it resolves against at `rulesets/layers/<digest>.xml` in its state directory, written once
and never rewritten, so a recipe's rules can be read back after its sidecar has changed.

#### Scenario: a layer outlives its sidecar
- **WHEN** a recipe is resolved through a container's rules, and the container's `<rules>` is then
  edited
- **THEN** the recipe still names the first digest, and the layer kept under it is the rules the
  recipe was resolved through

Pinned by: nothing yet.
