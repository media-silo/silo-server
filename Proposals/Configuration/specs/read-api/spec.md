<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## RENAMED Requirements

- FROM: `### Requirement: The operator's token gates mutation; the server is told itself through its environment`
- TO: `### Requirement: The operator's credential gates mutation; the server is told itself through its state directory`

## MODIFIED Requirements

### Requirement: The operator's credential gates mutation; the server is told itself through its state directory
Every mutation route on this surface — the scan and the ruleset store — SHALL
require the `Authorization` header to carry a bearer the operator credential
accepts, per [onboarding](../onboarding/spec.md); a missing or wrong bearer
SHALL be 401. No credential installed SHALL mean no operator route works, which
is the safe way round for a server otherwise open on a household network. The
read routes SHALL answer without any token. Of its environment the silo SHALL
read only `SILO_STATE_DIR`, before anything is served; everything else it is
told — where it listens and which libraries it serves — SHALL come from
`silo.json` and `settings.json` in its state directory, as
[configuration](../configuration/spec.md) sets out.

#### Scenario: the gate on the routes this spec owns
- **WHEN** a client puts `/v1/rulesets/household` with no `Authorization`
  header, or with `Bearer wrong`
- **THEN** the answer is 401 both times, while `Bearer secret` — the token the
  installed credential accepts — is 201, and a scan follows the same rule

#### Scenario: the environment the server reads
- **WHEN** the suite's server is brought up over a state directory whose
  `settings.json` names the library `main` and whose credential accepts
  `secret`
- **THEN** its environment is `SILO_STATE_DIR` alone, and the read routes
  answer under the library `main`

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`, `aScanIsAnOperatorsToo`).
