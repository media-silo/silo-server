<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The stored rulesets are read at their latest version, or the one asked for
`GET /v1/rulesets` SHALL answer 200 with one `RulesetSummary` per ruleset —
its `name`, its latest `version`, and `versions`, every version the silo holds
of it in ascending order. `GET /v1/rulesets/{name}` SHALL answer 200 with a
`RulesetDocument`: the `name`, the `version`, the `document` as the XML that
was stored, byte for byte, and the `reading` — the silo's reader's account of
the document: its extraction policy, each rule in document order with its
scope, its conditions, its action and the name a recipe calls it by (its `id`,
or `#n` for its 1-based position when it has none), and its output policy. The
reading SHALL name the ruleset by the name and version it was stored under,
whatever the document's own attributes say. A `version` query parameter SHALL
select a version other than the latest. A name the silo does not hold, or a
version it does not hold, SHALL be 404.

#### Scenario: the list, the latest and a named version
- **WHEN** `household` has been stored twice and a client asks
  `GET /v1/rulesets`, `GET /v1/rulesets/household` and
  `GET /v1/rulesets/household?version=1`
- **THEN** the list reads `household@2` with versions `[1, 2]`, the latest
  answers version 2, and version 1's `document` equals, byte for byte, the
  document first stored

#### Scenario: the reading names the rules as a recipe does
- **WHEN** a client asks `GET /v1/rulesets/household` for the household ruleset
- **THEN** the reading lists six rules in document order named `small-extras`,
  `lossless-main`, `commentary`, `#4`, `#5` and `#6`, the extraction policy
  embeddedAudio false, subtitles true, embeddedSubtitles true, and the output
  container `mkv`

#### Scenario: names and versions the silo does not hold
- **WHEN** a client asks `GET /v1/rulesets/household?version=9` or
  `GET /v1/rulesets/nothing`
- **THEN** the answer is 404

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`); the versions and the reading
are pinned by nothing yet.

### Requirement: Every ruleset store is a new version, and is the operator's
`PUT /v1/rulesets/{name}` with a JSON `RulesetDocument` SHALL store the
`document` as the name's next version — the latest plus one, or 1 for a new
name — and answer 201 with the version the silo assigned; a `version` in the
body SHALL be ignored on a store, since numbering is the silo's. A `basedOn` in
the body SHALL make the store conditional: it SHALL land only when the name's
latest version is `basedOn`, or, for `basedOn` 0, only when the name has no
version, and otherwise SHALL answer 409 with a `Problem` whose `detail` names
the latest version, storing nothing. A store with no `basedOn` SHALL be
unconditional. A document the ruleset reader refuses, or a name the store
refuses, SHALL NOT be stored, and the answer SHALL be 400 with a `Problem`
whose `detail` says why. The route is the operator's.

#### Scenario: two stores are numbered in order
- **WHEN** the operator puts the household ruleset at `/v1/rulesets/household`
  twice
- **THEN** the answers are 201 with `version` 1 and then 2

#### Scenario: a document that is not a ruleset is refused
- **WHEN** the operator puts a document testing `<when fact="nope" is="1"/>`
- **THEN** the answer is 400 with `not a fact a rule can test` in the problem
  detail, and nothing is stored

#### Scenario: a store based on a version that is no longer the latest
- **WHEN** `household` is at version 2 and the operator puts a document based
  on version 1
- **THEN** the answer is 409 naming version 2, and `household` stays at
  version 2

#### Scenario: a new name, and only a new name
- **WHEN** the operator puts a document at `/v1/rulesets/mobile` based on 0,
  and then puts another there based on 0
- **THEN** the first answers 201 with `version` 1 and the second 409

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`); `basedOn` is pinned by
nothing yet.

### Requirement: The resolver runs as a dry run
`POST /v1/rulesets/{name}/resolve` with a JSON `ResolveRequest` — the source's
`facts`, optional track `mappings` and an optional `document` — SHALL answer
200 with the `Recipe` the resolver makes: its `ruleset` as `name@version`, one
decision per source stream naming the `rule` that made it, the `output` policy,
the `layout`, and `warnings`. Without a `document` the recipe SHALL be resolved
against the ruleset's latest version, or the version `?version=` names, and a
ruleset or version the silo does not hold SHALL be 404. With a `document` the
recipe SHALL be resolved against that document, read as a check reads it, and
its `ruleset` SHALL carry the name and no version; a document the reader
refuses SHALL be 400 with the refusal as a check gives it, and a `document`
together with a `version` query SHALL be 400. A stream no rule decides SHALL be
422 with a `Problem` detail naming the stream. The route is a dry run: no
library, index or ruleset SHALL change because of it, and nothing is encoded.

#### Scenario: the recipe before anything is encoded
- **WHEN** a client posts the fixture's facts to
  `/v1/rulesets/household/resolve`
- **THEN** the 200 answer's decisions name the rules `small-extras`,
  `lossless-main` and `commentary`, and its ruleset reads `household@2`

#### Scenario: a stream no rule decides
- **WHEN** the same facts are posted against a ruleset whose only rule is a
  video catch-all
- **THEN** the answer is 422 with `no rule decides audio 1` in the problem
  detail

#### Scenario: a draft is resolved and not stored
- **WHEN** a client posts the fixture's facts to
  `/v1/rulesets/household/resolve` with a `document` in which the
  `commentary` rule's bitrate is `96k`
- **THEN** the 200 answer's commentary decision is `commentary` encoding AAC at
  96k, its ruleset names `household` with no version, and `household`'s latest
  version is unchanged

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`); a draft document is pinned by
nothing yet.

## ADDED Requirements

### Requirement: A document is checked as a store would read it, and nothing is stored
`POST /v1/rulesets/{name}/check` with a JSON `RulesetDocument` SHALL check the
name as a store checks it and read the `document` as a store reads it, and
SHALL answer 200 with the reading `GET /v1/rulesets/{name}` would give the
document once stored, less its version, or 400 with a `Problem` whose `detail`
is the one a store of the same name and document would give. It SHALL store
nothing, whatever its answer, and SHALL answer without a token.

#### Scenario: a good draft is read
- **WHEN** a client checks the household ruleset at `/v1/rulesets/household/check`
- **THEN** the answer is 200 with a reading of six rules, and no version of
  `household` is added

#### Scenario: a check refuses as a store refuses
- **WHEN** a client checks a document testing `<when fact="nope" is="1"/>`, and
  checks the household ruleset under the name `.hidden`
- **THEN** each answer is 400 with the detail a store of the same name and
  document answers, and nothing is stored

Pinned by: nothing yet.
