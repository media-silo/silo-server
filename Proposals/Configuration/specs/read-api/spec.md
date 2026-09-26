<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The operator's token gates mutation; the server is told itself through its environment
Every mutation route on this surface — the scan and the ruleset store — SHALL
require the `Authorization` header to carry the configured operator token as
`Bearer <token>`, matched exactly; a missing or wrong token SHALL be 401. No
token configured SHALL mean no operator route works, which is the safe way
round for a server otherwise open on a household network. The read routes
SHALL answer without any token. The silo SHALL read its environment once,
before anything is served, as [configuration](../configuration/spec.md) sets
out: its local settings, and the variables that pin its stored ones —
`SILO_LIBRARIES` as `name=path,name=path`, or one bare path, which is the
library `main`. A library the environment names whose path does not exist
SHALL stop the boot with an error naming the library.

#### Scenario: the gate on the routes this spec owns
- **WHEN** a client puts `/v1/rulesets/household` with no `Authorization`
  header, or with `Bearer wrong`
- **THEN** the answer is 401 both times, while `Bearer secret` — the token the
  environment configured — is 201, and a scan follows the same rule

#### Scenario: the environment the server reads
- **WHEN** the suite's server is brought up
- **THEN** its environment is `SILO_LIBRARIES`, `SILO_STATE_DIR` and
  `SILO_OPERATOR_TOKEN`, and the read routes answer under the library `main`

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`, `aScanIsAnOperatorsToo`).
