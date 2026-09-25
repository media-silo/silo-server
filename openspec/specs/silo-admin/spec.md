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
anything. For a silo that has gone quiet, it offers to forget — never on its own, only when
the operator says so: the passkey off this Mac, the registry empty of it, the row gone. A
passkey is never logged, never written to a file by the app, and never rendered in full again,
and the residue of an interrupted attempt is asked of the silo before anything is decided: a
still-standing stage is finished only by the operator's consent, a dead one quietly replaced.

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
SHALL not appear at all. A silo that stops answering SHALL never be removed by a refresh: it
renders unreachable, credentials and entry intact, and removal is the operator's act alone.

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
no passkey this Mac holds passes the probe, and the offered act is to claim it: never met and
none held are the same situation, but **held-then-refused** is not — a refusal earned while this
Mac held the passkey SHALL be told apart from a silo never entered, wherever the console speaks
of the silo; or **unreachable** — registered, and two consecutive sweeps have found no contact,
and the offered act is to forget it. The probe SHALL be `GET /v1/operator` with the stored
passkey as bearer — 200 is access and everything else is not — and SHALL only be attempted
against a reachable silo this Mac holds a passkey for. A single missed sweep SHALL change
nothing the operator can see — the silo keeps the last classification the console verified, and
only its last-seen time stands still — and the next contact SHALL render that sweep's verdict
at once, whatever it is: hysteresis damps the fall to unreachable, and nothing else.
Last-known-ness is row data, not a fifth class: each probe verdict SHALL be kept in the
registry, so an unreachable silo renders its last-seen time and last-known access rather than
being probed or dropped.

#### Scenario: the probe decides
- **WHEN** the app holds a passkey for a silo and probes it, then probes with a passkey the silo
  refuses
- **THEN** the silo classifies as with-access on the first probe and without-access on the
  second, and the refusal is kept as its last-known access

#### Scenario: one miss disturbs nothing
- **WHEN** a sweep finds no contact with a silo that answered the one before
- **THEN** the silo keeps the classification the console last verified, and only its last-seen
  time stands still

#### Scenario: unreachable is last-known, not unknown
- **WHEN** a silo the app had access to stops answering, and two consecutive sweeps find no
  contact
- **THEN** it renders as unreachable with its last-seen time, and last-known access shows the
  access it had

#### Scenario: contact heals at once
- **WHEN** a silo that missed one sweep answers the next
- **THEN** that sweep's true classification renders, the row never having shown unreachable

#### Scenario: held-then-refused is named
- **WHEN** a sweep's probe refuses a passkey this Mac holds
- **THEN** the silo classifies without access, and wherever the console speaks of it the refusal
  is named, not rendered as plain no-access

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`everyShownSiloIsExactlyOneClass`, `theProbeDecides`, `unreachableIsLastKnownNotUnknown`, `oneMissDisturbsNothing`, `contactHealsAtOnce`, `launchedIntoSilenceReadsTheRegistrysVerdicts`).

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
confirm never landed — the flow SHALL ask the silo what the residue amounts to before
deciding anything: a `pending` answer means the earlier stage still stands, and the sheet
SHALL offer to finish it, showing when the window shuts and asking the operator's consent —
finalising the passkey the earlier attempt showed, which is not shown again — and SHALL NOT
confirm on its own; the sheet consented to in this shape SHALL send the confirm alone,
re-staging nothing. A refused residue is dead, and the sheet SHALL mint and show a fresh
passkey, the new attempt's write-ahead overwriting the residue. The passkey SHALL NOT be
logged, written to files by the app, or displayed in full ever again. A `410` reply SHALL end
the flow, discard the passkey minted for that attempt, and leave the silo classified by its
probe result — any passkey the Keychain already holds for the ServerID stays, and the probe
resolves the truth honestly. A `409` reply SHALL tell the operator that a setup is staged
elsewhere and when its window runs out, and SHALL store nothing.

#### Scenario: setup from the chair
- **WHEN** the operator confirms the setup sheet for a bootstrap silo
- **THEN** the stage succeeds, the passkey is in the Keychain under the silo's ServerID before
  the confirm is sent, the confirm answers 201, and the silo shows as with-access

#### Scenario: a live stage is finished by consent
- **WHEN** the Keychain holds the residue of an attempt whose stage still stands, and the
  operator opens the setup sheet
- **THEN** the sheet offers to finish the staged setup, showing when its window shuts and
  that confirming finalises the passkey the earlier attempt showed — which is not shown
  again — and the operator's consent sends the confirm alone, staging nothing anew

#### Scenario: a dead residue is replaced
- **WHEN** the Keychain holds a residue the silo refuses — its stage expired or was never
  this console's — and the operator opens the setup sheet
- **THEN** the sheet mints and shows a fresh passkey, and the new attempt's Keychain
  write-ahead overwrites the residue

#### Scenario: someone else got there first
- **WHEN** the stage call is refused with 410
- **THEN** the passkey minted for that attempt is discarded, any passkey the Keychain already
  holds for the ServerID stays, and the silo is classified by what its probe says

#### Scenario: setup staged elsewhere
- **WHEN** the stage call is refused with 409
- **THEN** nothing is stored, and the operator is shown that a setup is already staged and when
  its window runs out

Pinned by: `Tests/SiloAdminKitTests/PasskeyTests.swift` (`theMintIs128BitsOfLettersAndDigits`, `theGroupingFollowsTheAlphabet`), `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`setupFromTheChair`, `aLiveStageIsFinishedByConsent`, `aDeadResidueIsReplaced`, `someoneElseGotThereFirst`, `setupStagedElsewhere`).

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
