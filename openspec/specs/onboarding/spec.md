<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Onboarding

## Purpose

How a silo with no configuration becomes a known server. The silo mints and keeps its own
identity, says who it is on an open route, and computes bootstrap as a state — nothing in the
state directory and nothing in the environment — never a flag. The operator credential lives in
the environment first and the state directory second, stored as a hash and never as the passkey.

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

### Requirement: Bootstrap is the absence of an operator credential
A silo SHALL be in bootstrap when it holds no operator credential — no `operator-credential.json`
in its state directory and no `SILO_OPERATOR_TOKEN` in its environment; an operator credential
arriving by either path SHALL end it, and once ended no boot SHALL re-enter it. In bootstrap the
silo SHALL behave as a silo with no operator token does today — reads served, operator routes
refused with 401.

#### Scenario: the empty case
- **WHEN** a silo boots over an empty state directory with no `SILO_OPERATOR_TOKEN`
- **THEN** it is in bootstrap, and refuses every operator bearer with 401

#### Scenario: a credential ends it
- **WHEN** an operator credential is installed — or `SILO_OPERATOR_TOKEN` is set — over a silo
  that was in bootstrap
- **THEN** the silo is no longer in bootstrap, and its operator gate takes the credential's bearer

Pinned by: `Tests/SiloTests/OperatorCredentialTests.swift` (`bootstrapIsTheAbsenceOfACredentialOrAnEnvironmentToken`).

### Requirement: The silo stores only the hash of the operator passkey, and the environment wins
The operator credential SHALL be kept at `operator-credential.json` in the state directory as
the SHA-256 of the passkey, as hex — never the passkey itself — and writes SHALL be atomic. The
operator gate SHALL accept a bearer whose hash matches the stored credential, and SHALL continue
to accept the `SILO_OPERATOR_TOKEN` value, which takes precedence whenever it is set. A boot
over a state directory holding the credential SHALL authenticate its bearer across restarts.

#### Scenario: the passkey survives a restart
- **WHEN** a credential was installed and a fresh process opens the same state directory
- **THEN** the passkey's bearer passes the operator gate, and the JSON on disk contains a hash and
  never the passkey

#### Scenario: the environment wins
- **WHEN** `SILO_OPERATOR_TOKEN` is set over a state directory that also holds a credential
- **THEN** the environment's token passes and the stored credential's does not

Pinned by: `Tests/SiloTests/OperatorCredentialTests.swift` (`theCredentialSurvivesARestartAsAHash`, `theEnvironmentWinsOverTheStoredCredential`).
