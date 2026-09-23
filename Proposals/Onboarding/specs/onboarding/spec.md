<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

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

Pinned by: nothing yet.

### Requirement: /v1/server is an open route that reports the server's identity
The silo SHALL serve `GET /v1/server` with a `ServerInfo` — the server's `id`, its current `name`,
and whether it is in `bootstrap` — and SHALL document the operation in the OpenAPI document. The
route SHALL be open: everything it reports is already visible in the Bonjour advertisement, and
nothing it reports is a credential.

#### Scenario: what a stranger can learn
- **WHEN** `GET /v1/server` is called without any token
- **THEN** the reply is 200 with the server's id, name and bootstrap state

Pinned by: nothing yet.

### Requirement: Bootstrap is the absence of an operator credential, and setup fires once
A silo SHALL be in bootstrap when it holds no operator credential — no `operator-credential.json`
in its state directory and no `SILO_OPERATOR_TOKEN` in its environment. In bootstrap the silo
SHALL behave as a silo with no operator token does today — reads served, operator routes refused
with 401 — except that it SHALL also serve `POST /v1/setup`, taking a `SetupRequest` (an optional
`name`, and a `passkey`) and answering 201 with the server's `ServerInfo`. On success the silo
SHALL store the SHA-256 of the passkey as the operator credential and record the name, SHALL write
both atomically, and SHALL thereby leave bootstrap. `POST /v1/setup` on a server that is not in
bootstrap SHALL answer 410 `gone`, including immediately after the one success and across
restarts, and no network route SHALL return a server to bootstrap.

#### Scenario: setup once, then gone
- **WHEN** `POST /v1/setup` succeeds on a bootstrap silo and is then called again
- **THEN** the replies are 201 and 410, and after a restart the route still answers 410

#### Scenario: the empty case refuses
- **WHEN** `POST /v1/setup` arrives with an empty `passkey`
- **THEN** the reply is 400 and the silo remains in bootstrap

Pinned by: nothing yet.

### Requirement: The silo stores only the hash of the operator passkey
The operator credential installed by setup SHALL be kept at `operator-credential.json` in the
state directory as the SHA-256 of the passkey, as hex — never the passkey itself. The operator
gate SHALL accept a bearer whose hash matches the stored credential, and SHALL continue to accept
the `SILO_OPERATOR_TOKEN` value, which takes precedence whenever it is set. A boot over a state
directory holding the credential SHALL authenticate its bearer across restarts.

#### Scenario: the passkey survives a restart
- **WHEN** a silo was set up and a fresh process opens the same state directory
- **THEN** the passkey's bearer passes the operator gate, and the JSON on disk contains a hash and
  never the passkey

#### Scenario: the environment wins
- **WHEN** `SILO_OPERATOR_TOKEN` is set over a state directory that also holds a credential
- **THEN** the environment's token passes and the stored credential's does not

Pinned by: nothing yet.

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

Pinned by: nothing yet.
