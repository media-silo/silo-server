<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The resolver runs as a dry run
`POST /v1/rulesets/{name}/resolve` with a JSON `ResolveRequest` — one or more input specs, joined in
order as a binding's segments are, and what a binding would add to them: the optional `kind`, the
`roles` of the audio streams a feature map names, and the track `mappings` for renumbering — SHALL
answer 200 with a `Recipe` for each of the ruleset's outputs, in the ruleset's order, resolved
against its latest version, or the version `?version=` names: each with its `ruleset` as
`name@version`, its output, one decision per stream naming the `rule` that made it, the `layout`,
and `warnings`. A ruleset or version the silo does not hold SHALL be 404; an input spec the silo
refuses, or specs that cannot be joined, SHALL be 400 with the reason; and a stream no rule decides
for any output SHALL be 422 with a `Problem` detail naming the stream and the output. The route is a
dry run: no source, binding, recipe, job, library, index or ruleset SHALL change because of it, and
nothing is encoded.

#### Scenario: the recipe before anything is encoded
- **WHEN** a client posts the input spec of an episode with a lossless main mix and a commentary to
  `/v1/rulesets/household/resolve`, `household` being at version 2 with one output
- **THEN** the 200 answer holds one recipe, whose decisions name the rules `lossless-main` and
  `commentary` for the two audio streams, and whose ruleset reads `household@2`

#### Scenario: a stream no rule decides
- **WHEN** the same input spec is posted against a ruleset whose only rule is a video catch-all
- **THEN** the answer is 422 with `no rule decides audio 1` in the problem detail

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`).
