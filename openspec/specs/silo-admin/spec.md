<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# SiloAdmin

## Purpose

The operator's console on a Mac. SiloAdmin browses Bonjour and typed addresses, merges what it
finds into a persisted registry keyed by `ServerID`, and shows every silo it knows as exactly
one of four classes — bootstrap, with access, without access, unreachable — deciding access by
asking the silo, never by remembering. For a bootstrap silo it mints the 128-bit passkey, shows
it to the operator exactly once, and installs it with the Keychain write ahead of the confirm,
so the silo can never become configured while the app holds no copy. For a silo it holds no
passkey for, it claims with what the operator types, verifying by probe before it keeps
anything. For a silo that has gone quiet, it forgets: the passkey off this Mac, the registry
empty of it, the row gone. A passkey is never logged, never written to a file by the app, and
never rendered in full again.

Rationale: [Silo proposal — Onboarding](../../../Proposals/Onboarding.md) — the console
remembers silos; access is always asked of the silo.

## Requirements

### Requirement: SiloAdmin keeps a registry of the silos it has seen
The `SiloAdmin` app SHALL keep a persisted registry of silos, keyed by `ServerID`, recording for
each the name it last used, the URL it last answered at, when it was last seen, and whether a
passkey is stored for it. Browsing Bonjour SHALL merge into the registry — creating entries for
silos never seen, refreshing `last-seen` and the last-known address for ones it has — and an
address typed by the operator SHALL be resolved through `GET /v1/server` and merged the same way.
The registry SHALL survive an app restart. A silo that is neither in the registry nor reachable
SHALL not appear at all.

#### Scenario: browsing refreshes, never forgets
- **WHEN** the app launches and browses a network where a previously seen silo is absent and a
  bootstrap silo is present
- **THEN** the absent silo still renders, with its last-seen time, and the bootstrap silo is added
  to the registry

Pinned by: `Tests/SiloAdminKitTests/SiloRegistryTests.swift` (`aRestartKeepsTheRegistry`), `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`browsingRefreshesNeverForgets`, `aTypedAddressResolvesAndMerges`).

### Requirement: Every silo the app shows is exactly one class
SiloAdmin SHALL classify each silo it shows as one of: **bootstrap** — the live advertisement or
`GET /v1/server` says so, and the offered act is to set it up; **with access** — reachable, and
this Mac's passkey passed the probe, and no act is offered; **without access** — reachable, but
no passkey this Mac holds passes the probe: never met, none held, and held-then-refused are the
same situation, and the offered act is to claim it; or **unreachable** — registered but no
longer answering, and the offered act is to forget it. The probe SHALL be `GET /v1/operator`
with the stored passkey as bearer — 200 is access and everything else is not — and SHALL only
be attempted against a reachable silo this Mac holds a passkey for. Last-known-ness is row
data, not a fifth class: each probe verdict SHALL be kept in the registry, so an unreachable
silo renders its last-seen time and last-known access rather than being probed or dropped.

#### Scenario: the probe decides
- **WHEN** the app holds a passkey for a silo and probes it, then probes with a passkey the silo
  refuses
- **THEN** the silo classifies as with-access on the first probe and without-access on the
  second, and the refusal is kept as its last-known access

#### Scenario: unreachable is last-known, not unknown
- **WHEN** a silo the app had access to stops answering
- **THEN** it renders as unreachable with its last-seen time, and last-known access shows the
  access it had

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`everyShownSiloIsExactlyOneClass`, `theProbeDecides`, `unreachableIsLastKnownNotUnknown`).

### Requirement: Forgetting purges the silo and its passkey
For an unreachable silo, SiloAdmin SHALL offer to forget it. Forgetting SHALL delete any passkey
this Mac holds for the silo's `ServerID`, SHALL remove the silo's entry from the registry, and
SHALL drop its row from the rendered list. If the silo answers again afterwards, it SHALL
arrive as never met — a fresh registry entry, no stored passkey, no last-known access.

#### Scenario: forget purges the registry and the passkey
- **WHEN** the operator forgets an unreachable silo
- **THEN** the Keychain holds no passkey for it, the registry holds no entry for it, and its row
  leaves the rendered list

#### Scenario: a rediscovery restarts history
- **WHEN** a forgotten silo answers a browse again
- **THEN** it merges into the registry as a fresh contact with no passkey and no last-known
  access, and classifies without-access

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`forgetPurgesTheRegistryAndThePasskey`, `aRediscoveryRestartsHistory`).

### Requirement: The setup flow mints the passkey, shows it once, and installs it
For a bootstrap silo, SiloAdmin SHALL generate a random 128-bit passkey, render it for a human
to transcribe, and display it exactly once with an offer to copy it. On the operator's
confirmation it SHALL play the setup pair in order — `POST /v1/setup` with the passkey and an
optional name, the passkey into its Keychain keyed by the silo's `ServerID`, then
`POST /v1/setup/confirm` with the passkey as bearer — and the Keychain write SHALL precede the
confirm, so the silo cannot become configured while the app holds no copy. On a confirmed setup
it SHALL record the silo in its registry and classify it with-access. If the Keychain
already holds a passkey for a bootstrap silo's ServerID — the residue of an attempt whose
confirm never landed — the flow SHALL reuse that passkey rather than minting afresh. The
passkey SHALL NOT be logged, written to files by the app, or displayed in full ever again. A
`410` reply SHALL end the flow, discard the passkey minted for that attempt, and leave the
silo classified by its probe result — any passkey the Keychain already holds for the ServerID
stays, and the probe resolves the truth honestly. A `409` reply SHALL tell the operator that a
setup is staged elsewhere and when its window runs out, and SHALL store nothing.

#### Scenario: setup from the chair
- **WHEN** the operator confirms the setup sheet for a bootstrap silo
- **THEN** the stage succeeds, the passkey is in the Keychain under the silo's ServerID before
  the confirm is sent, the confirm answers 201, and the silo shows as with-access

#### Scenario: an interrupted setup resumes with the same passkey
- **WHEN** an earlier attempt staged a setup whose confirm never landed, its stage has expired,
  and the operator retries setup on the still-bootstrap silo
- **THEN** the new stage sends the passkey already in the Keychain for that ServerID, the
  confirm succeeds, and the silo shows as with-access

#### Scenario: someone else got there first
- **WHEN** the stage call is refused with 410
- **THEN** the passkey minted for that attempt is discarded, any passkey the Keychain already
  holds for the ServerID stays, and the silo is classified by what its probe says

#### Scenario: setup staged elsewhere
- **WHEN** the stage call is refused with 409
- **THEN** nothing is stored, and the operator is shown that a setup is already staged and when
  its window runs out

Pinned by: `Tests/SiloAdminKitTests/PasskeyTests.swift` (`theMintIs128BitsOfLettersAndDigits`, `theGroupingFollowsTheAlphabet`), `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`setupFromTheChair`, `anInterruptedSetupResumesWithTheSamePasskey`, `someoneElseGotThereFirst`, `setupStagedElsewhere`).

### Requirement: Claiming is entering the passkey, and the probe is the verdict
For a silo classified without-access, SiloAdmin SHALL offer to claim it with a passkey the
operator supplies. The supplied passkey SHALL be verified by the probe before it is
stored; a passing probe SHALL store the passkey in the Keychain, merge the silo into the
registry, and classify it with-access, and a refused probe SHALL store nothing.

#### Scenario: wrong passkey, nothing kept
- **WHEN** the operator claims a silo with a passkey the silo refuses
- **THEN** the Keychain and the registry hold no passkey for that ServerID and the silo stays
  without-access

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`wrongPasskeyNothingKept`, `aClaimVerifiesBeforeItStores`).
