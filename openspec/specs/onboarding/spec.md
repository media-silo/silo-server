<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Onboarding

## Purpose

How a silo with no configuration becomes a known server. The silo mints and keeps its own
identity, says who it is on an open route, and computes bootstrap as a state — nothing in the
state directory and nothing in the environment — never a flag. While bootstrap lasts the silo
serves the setup pair: a passkey staged in memory for ten minutes, and a confirm whose one spend
ends bootstrap for good. The operator credential lives in the environment first and the state
directory second, stored as a hash and never as the passkey; recovery is the filesystem's own act,
a reset file at boot, deliberate and loud.

Rationale: [Silo proposal — Onboarding](../../../Proposals/Onboarding.md) — bootstrap is the
empty case; the identity is minted once; the passkey is never stored.

## Requirements

### Requirement: The silo mints a ServerID once and keeps it
The silo SHALL, on a boot that finds no `server.json` in its state directory, mint a server
identity — a `ServerID`, a lower-cased UUID — and a name, seeded from `SILO_NAME` and defaulting
to `Silo on <host name>`, and SHALL write both atomically to `server.json`; a boot that finds the
file SHALL load and reuse it. The file SHALL thereafter be the source of truth for the silo's
name: `SILO_NAME` is consulted when minting and when minting only. The operator changing the state
directory's contents is the supported way to make a new server; no route SHALL re-mint the
identity.

#### Scenario: first boot
- **WHEN** the silo starts with an empty state directory
- **THEN** it writes `server.json` holding a fresh ServerID and the default name, and serves that
  identity

#### Scenario: later boots
- **WHEN** the silo starts over a state directory an earlier boot used
- **THEN** it serves the same ServerID and name, with `SILO_NAME` making no difference

Pinned by: `Tests/SiloTests/ServerIdentityTests.swift` (`identityIsMintedOnceAndKeptAcrossRestartsAndARename`).

### Requirement: /v1/server is an open route that reports the server's identity
The silo SHALL serve `GET /v1/server` with a `ServerInfo` — the server's `id`, its current `name`,
and whether it is in `bootstrap` — and SHALL document the operation in the OpenAPI document. The
route SHALL be open: everything it reports is already visible in the Bonjour advertisement, and
nothing it reports is a credential.

#### Scenario: what a stranger can learn
- **WHEN** `GET /v1/server` is called without any token
- **THEN** the reply is 200 with the server's id, name and bootstrap state

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theServerRouteAnswersOpenly`).

### Requirement: The verify-access route names what its bearer amounts to, and nothing else
The silo SHALL serve `GET /v1/operator` as the route whose whole job is telling a bearer what it
holds. With the operator's bearer it SHALL answer 200 with an `OperatorStatus` of
`{"phase":"active"}`; with the live staged passkey it SHALL answer 200 with
`{"phase":"pending","confirmBy":...}` carrying the stage's deadline, so a console that staged a
setup and kept the passkey can learn the stage still stands and when it shuts. With any other
bearer, or none, it SHALL answer 401 with an empty body.

The two halves of the 200 SHALL disclose no more than the phase and, for a pending stage, its
`confirmBy`: neither the id, nor the name, nor the bootstrap flag rides on this route. The
pending answer discloses nothing a stranger could not learn by attempting their own stage and
being answered 409 with the same `confirmBy`, and it SHALL reach only the bearer that is the
staged passkey — the staged secret is the stager's own, so to its own holder nothing is given
away. The staged passkey SHALL be answered by this route alone: every other operator route
SHALL keep refusing it with 401. The verification SHALL NOT depend on any other subsystem — it
is the node's list, its jobs, and the library's health in no part — so that a 401 names the
token and only the token.

#### Scenario: the answer is the gate itself
- **WHEN** `GET /v1/operator` is called without a bearer, called with a refused bearer, and
  called with the operator's bearer
- **THEN** the replies are 401 with an empty body, 401 with an empty body, and 200 with
  `{"phase":"active"}`

#### Scenario: the staged passkey learns its stage stands
- **WHEN** a setup is staged and `GET /v1/operator` is called with the staged passkey as its
  bearer before the window shuts
- **THEN** the reply is 200 with `{"phase":"pending","confirmBy":...}` naming the stage's
  deadline

#### Scenario: a spent or void stage is a dead bearer
- **WHEN** the staged passkey is asked after on `GET /v1/operator` after the stage expired or
  was confirmed
- **THEN** the reply is 401 with an empty body, the expiry or the confirm having voided it like
  any other bearer that is not the operator's

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theVerifyRouteAnswersOnlyTheOperator`), `Tests/SiloTests/SetupTests.swift` (`aLiveStageAnswersItsOwnBearerPending`, `aConfirmedStageStopsAnsweringItsPasskey`), `Tests/SiloClientTests/SiloClientTests.swift` (`theVerifyProbeSendsTheToken`, `aPendingVerifyCarriesTheStagesWindow`, `aRefusedVerifyArrivesAsAStatus`).

### Requirement: Bootstrap is the absence of an operator credential, and only a confirmed setup ends it
A silo SHALL be in bootstrap when it holds no operator credential — no `operator-credential.json`
in its state directory and no `SILO_OPERATOR_TOKEN` in its environment; a staged but unconfirmed
setup SHALL NOT end bootstrap. In bootstrap the silo SHALL behave as a silo with no operator
token does today — reads served, operator routes refused with 401 — except that it SHALL also
serve the setup pair: `POST /v1/setup` and `POST /v1/setup/confirm`.

`POST /v1/setup` SHALL take a `SetupRequest` (an optional `name`, and a `passkey`), stage the
passkey and name in memory with a deadline ten minutes hence, and answer 202 with the staged
setup — the `ServerID`, the name it would take, and the `confirmBy` timestamp — writing nothing
to the state directory. While a stage is pending and unexpired, a further `POST /v1/setup`
SHALL answer 409 carrying the standing stage's `confirmBy`, so a refused console knows how long
there is to wait out; once the deadline passes the stage SHALL be void and the route SHALL stage
anew. On a server that is not in bootstrap the route SHALL answer 410 `gone`, across restarts,
and no network route SHALL return a server to bootstrap.

`POST /v1/setup/confirm` SHALL take the staged passkey as its bearer. A bearer matching the
pending stage SHALL install the credential and the name — the SHA-256 of the passkey and the
name written to state atomically — answer 201 with the server's `ServerInfo`, and thereby leave
bootstrap. A bearer that does not match SHALL answer 401 and leave the stage standing. With
nothing staged — expired, restarted, or attempted on a configured server — the route SHALL
answer 404.

#### Scenario: setup once, then gone
- **WHEN** `POST /v1/setup` is staged and confirmed, and `POST /v1/setup` is then called again
- **THEN** the replies are 202, 201 and 410, and after a restart the route still answers 410

#### Scenario: the empty case refuses
- **WHEN** `POST /v1/setup` arrives with an empty `passkey`
- **THEN** the reply is 400, nothing is staged, and the silo remains in bootstrap

#### Scenario: an unconfirmed stage expires
- **WHEN** a staged setup's `confirmBy` passes with no confirm received
- **THEN** the staged passkey's confirm answers 404 and a fresh `POST /v1/setup` stages anew

#### Scenario: two stages collide
- **WHEN** a second `POST /v1/setup` arrives while a stage's window is still open
- **THEN** it answers 409 with the first stage's `confirmBy`, and the first stage remains
  confirmable

#### Scenario: a wrong confirm does no damage
- **WHEN** `POST /v1/setup/confirm` carries a bearer that is not the staged passkey
- **THEN** it answers 401, and a confirm with the staged passkey still succeeds

#### Scenario: a restart forgets the stage
- **WHEN** the silo restarts with a setup staged but unconfirmed
- **THEN** the state directory holds no credential, the confirm answers 404, and
  `POST /v1/setup` stages anew

Pinned by: `Tests/SiloTests/SetupTests.swift` (`aConfirmedSetupEndsBootstrapAndTheRouteIsGoneThereafter`, `anEmptyPasskeyIsRefused`, `anUnconfirmedStageExpires`, `twoStagesCollideAndTheFirstStillConfirms`, `aWrongConfirmDoesNoDamage`, `aRestartForgetsTheStage`), `Tests/SiloTests/ServerTests.swift` (`theSetupPairStaysShutWhereACredentialStands`), `Tests/SiloTests/OperatorCredentialTests.swift` (`bootstrapIsTheAbsenceOfACredentialOrAnEnvironmentToken`).

### Requirement: The silo stores only the hash of the operator passkey, and the environment wins
The operator credential SHALL be kept at `operator-credential.json` in the state directory as
the SHA-256 of the passkey, as hex — never the passkey itself — and writes SHALL be atomic. A
staged passkey SHALL be held in memory only; none of it SHALL reach the state directory before
its confirm. The operator gate SHALL accept a bearer whose hash matches the stored credential,
and SHALL continue to accept the `SILO_OPERATOR_TOKEN` value, which takes precedence whenever it
is set. A boot over a state directory holding the credential SHALL authenticate its bearer
across restarts.

#### Scenario: the passkey survives a restart
- **WHEN** a credential was installed and a fresh process opens the same state directory
- **THEN** the passkey's bearer passes the operator gate, and the JSON on disk contains a hash and
  never the passkey

#### Scenario: the environment wins
- **WHEN** `SILO_OPERATOR_TOKEN` is set over a state directory that also holds a credential
- **THEN** the environment's token passes and the stored credential's does not

Pinned by: `Tests/SiloTests/OperatorCredentialTests.swift` (`theCredentialSurvivesARestartAsAHash`, `theEnvironmentWinsOverTheStoredCredential`), `Tests/SiloTests/SetupTests.swift` (`aConfirmedSetupEndsBootstrapAndTheRouteIsGoneThereafter`).

### Requirement: Recovery is through the filesystem, deliberate and loud
At boot, when `operator-credential.reset` exists in the state directory, the silo SHALL read a new
operator token from it, store its SHA-256 as the operator credential, delete the file, and log the
reset at a level an operator cannot miss. An empty or whitespace-only file SHALL be ignored and
logged. No network route SHALL offer this effect. A reset does not return the silo to bootstrap:
the server SHALL leave the boot with a credential set.

#### Scenario: the reset file rotates the credential
- **WHEN** `operator-credential.reset` holds a new token and the silo boots
- **THEN** the old passkey is refused, the new token passes, the file is gone, and the log records
  the reset

#### Scenario: an empty file is no door
- **WHEN** `operator-credential.reset` exists but is empty
- **THEN** it is removed, logged, and the operator credential is unchanged

Pinned by: `Tests/SiloStoreTests/OperatorCredentialResetTests.swift` (`theResetFileRotatesTheCredential`, `anEmptyFileIsNoDoor`, `noFileIsNoReset`).
