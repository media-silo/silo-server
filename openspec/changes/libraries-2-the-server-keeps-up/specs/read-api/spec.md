<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## REMOVED Requirements

### Requirement: A scan re-reads what changed, and is the operator's to run
**Reason**: Keeping the index current becomes the server's job
([index-and-rulesets](../index-and-rulesets/spec.md)); nothing is left for a requested scan to do.
**Migration**: The route's answer — the counts and findings — is read from
`GET /v1/libraries/{library}/scan`, which reports the last walk.

## MODIFIED Requirements

### Requirement: The operator's credential gates mutation; the server is told itself through its state directory
Every mutation route on this surface — the library routes and the ruleset
store — and the last-walk read SHALL
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
  installed credential accepts — is 201, and the last-walk read follows the same rule

#### Scenario: the environment the server reads
- **WHEN** the suite's server is brought up over a state directory whose
  `settings.json` names the library `main` and whose credential accepts
  `secret`
- **THEN** its environment is `SILO_STATE_DIR` alone, and the read routes
  answer under the library `main`

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`, `aScanIsAnOperatorsToo`).

## ADDED Requirements

### Requirement: The last walk of a library is read, never requested
The silo SHALL keep the report of each library's most recent walk and SHALL serve it at
`GET /v1/libraries/{library}/scan`, behind the operator gate, answering 200 with when the walk ran,
whether the library is available, and a `ScanReport` — the counts `read`, `unchanged`, `removed` and
the `findings`, each a `severity` of `error` or `warning` with an optional `path` and its `text`. A
library the silo does not serve SHALL be 404. No route SHALL start a walk on request.

#### Scenario: the last walk and its findings
- **WHEN** the operator reads `/v1/libraries/main/scan` after a walk that found an orphaned sidecar
- **THEN** the 200 answer carries when the walk ran and the warning `a sidecar nothing references`

#### Scenario: a library the silo does not serve
- **WHEN** the operator reads `/v1/libraries/other/scan`
- **THEN** the answer is 404

Pinned by: nothing yet.
