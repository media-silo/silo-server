<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The resolver runs as a dry run
`POST /v1/rulesets/{name}/resolve` with a JSON `ResolveRequest` — a mezzanine's `input` spec, and
what an assignment would add to it: the optional `kind`, `profile` and `format`, the `roles` of the
audio streams a feature map names, the track `mappings` for renumbering, and optional
`adjustments` — SHALL answer 200 with the `Recipe` an assignment of the same would record, resolved
against the ruleset's latest version, or the version `?version=` names: its `ruleset` as
`name@version`, one decision per stream naming the `rule` that made it and, for an adjusted stream,
the action the rule chose and the note, the `output` policy, the `layout`, and `warnings`. A
ruleset or version the silo does not hold SHALL be 404; an input spec the silo refuses, or an
adjustment the resolver refuses, SHALL be 400 with the reason; and a stream no rule decides SHALL
be 422 with a `Problem` detail naming the stream. The route is a dry run: no library, index, job or
ruleset SHALL change because of it, and nothing is encoded.

#### Scenario: the recipe before anything is encoded
- **WHEN** a client posts the input spec of an episode with a lossless main mix and a commentary to
  `/v1/rulesets/household/resolve`, `household` being at version 2
- **THEN** the 200 answer's decisions name the rules `lossless-main` and `commentary` for the two
  audio streams, and its ruleset reads `household@2`

#### Scenario: a stream no rule decides
- **WHEN** the same input spec is posted against a ruleset whose only rule is a video catch-all
- **THEN** the answer is 422 with `no rule decides audio 1` in the problem detail

#### Scenario: the adjusted recipe previewed
- **WHEN** the same input spec is posted with an adjustment giving audio 1 `copy`
- **THEN** the 200 answer copies audio 1, and its decision still names `lossless-main` and records
  that the rule chose FLAC

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`); adjustments are pinned by nothing yet.
