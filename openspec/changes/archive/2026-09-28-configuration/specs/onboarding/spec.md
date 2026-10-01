<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The silo mints a ServerID once and keeps it
The silo SHALL, on a boot that finds no ServerID in `silo.json` in its state directory, mint one — a
lower-cased UUID — and write it there, as [configuration](../configuration/spec.md) sets out; a boot
that finds one SHALL reuse it. No route SHALL write the ServerID. The silo's name SHALL NOT be part
of its identity: it SHALL live in `settings.json`, defaulting at first boot to `Silo on <host
name>`, and setup and the settings route SHALL change it without changing the ServerID. The operator
changing the state directory's contents is the supported way to make a new server; no route SHALL
re-mint the identity.

#### Scenario: first boot
- **WHEN** the silo starts with an empty state directory
- **THEN** `silo.json` holds a fresh ServerID, `settings.json` holds the default name, and the silo
  serves that identity

#### Scenario: later boots
- **WHEN** the silo starts over a state directory an earlier boot used
- **THEN** it serves the same ServerID and name

#### Scenario: a rename keeps the identity
- **WHEN** the silo is renamed and restarted
- **THEN** it serves the new name and the same ServerID

Pinned by: `Tests/SiloTests/ServerIdentityTests.swift` (`identityIsMintedOnceAndKeptAcrossRestartsAndARename`).

### Requirement: Bootstrap is the absence of an operator credential, and only a confirmed setup ends it
A silo SHALL be in bootstrap when it holds no operator credential — no `operator-credential.json`
in its state directory; a staged but unconfirmed
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
pending stage SHALL install the credential and the name — the name written to `settings.json`
first and the SHA-256 of the passkey to `operator-credential.json` last, each atomically — answer 201 with the server's `ServerInfo`, and thereby leave
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

Pinned by: `Tests/SiloTests/SetupTests.swift` (`aConfirmedSetupEndsBootstrapAndTheRouteIsGoneThereafter`, `anEmptyPasskeyIsRefused`, `anUnconfirmedStageExpires`, `twoStagesCollideAndTheFirstStillConfirms`, `aWrongConfirmDoesNoDamage`, `aRestartForgetsTheStage`), `Tests/SiloTests/ServerTests.swift` (`theSetupPairStaysShutWhereACredentialStands`), `Tests/SiloTests/OperatorCredentialTests.swift` (`bootstrapIsTheAbsenceOfACredential`).

### Requirement: Recovery is through the filesystem, deliberate and loud
At boot, when `operator-credential.reset` exists in the state directory, the silo SHALL read a new
operator token from it, store its SHA-256 as the operator credential, delete the file, and log the
reset at a level an operator cannot miss. An empty or whitespace-only file SHALL be ignored and
logged. No network route SHALL offer this effect. A reset does not return the silo to bootstrap:
the server SHALL leave the boot with a credential set. The same file placed in a state directory that
holds no credential SHALL install the first one, so a silo arriving configured never enters
bootstrap.

#### Scenario: the reset file rotates the credential
- **WHEN** `operator-credential.reset` holds a new token and the silo boots
- **THEN** the old passkey is refused, the new token passes, the file is gone, and the log records
  the reset

#### Scenario: arriving configured
- **WHEN** `operator-credential.reset` holds a token in a state directory the silo has never booted
  over, and the silo boots
- **THEN** the token passes the operator gate, the file is gone, and the silo is not in bootstrap

#### Scenario: an empty file is no door
- **WHEN** `operator-credential.reset` exists but is empty
- **THEN** it is removed, logged, and the operator credential is unchanged

Pinned by: `Tests/SiloStoreTests/OperatorCredentialResetTests.swift` (`theResetFileRotatesTheCredential`, `anEmptyFileIsNoDoor`, `noFileIsNoReset`). Arriving configured is pinned by nothing yet.

## REMOVED Requirements

### Requirement: The silo stores only the hash of the operator passkey, and the environment wins
**Reason**: `SILO_OPERATOR_TOKEN` is retired; the silo reads no environment but `SILO_STATE_DIR`
([configuration](../configuration/spec.md)), so there is no environment to win.
**Migration**: An operator token given before the first boot is `operator-credential.reset` placed in
the state directory. The hash-only storage this requirement also carried is restated, without the
environment, as "The silo stores only the hash of the operator passkey".

## ADDED Requirements

### Requirement: The silo stores only the hash of the operator passkey
The operator credential SHALL be kept at `operator-credential.json` in the state directory as
the SHA-256 of the passkey, as hex — never the passkey itself — and writes SHALL be atomic. A
staged passkey SHALL be held in memory only; none of it SHALL reach the state directory before
its confirm. The operator gate SHALL accept a bearer whose hash matches the stored credential and
no other. A boot over a state directory holding the credential SHALL authenticate its bearer
across restarts.

#### Scenario: the passkey survives a restart
- **WHEN** a credential was installed and a fresh process opens the same state directory
- **THEN** the passkey's bearer passes the operator gate, and the JSON on disk contains a hash and
  never the passkey

Pinned by: `Tests/SiloTests/OperatorCredentialTests.swift` (`theCredentialSurvivesARestartAsAHash`), `Tests/SiloTests/SetupTests.swift` (`aConfirmedSetupEndsBootstrapAndTheRouteIsGoneThereafter`).
