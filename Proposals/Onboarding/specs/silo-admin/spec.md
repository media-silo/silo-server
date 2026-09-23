<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

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

Pinned by: nothing yet.

### Requirement: Every silo the app shows is exactly one class
SiloAdmin SHALL classify each silo it shows as one of: **bootstrap** — the live advertisement or
`GET /v1/server` says so; **unseen** — reachable and not in the registry; **seen, has access** —
in the registry with a stored passkey whose probe passes; or **seen, no access** — in the
registry without a stored passkey, or whose probe is refused. The probe SHALL be `GET /v1/nodes`
with the stored passkey as bearer: 200 is access, 401 is no access, and the probe SHALL only be
attempted against a reachable silo. An unreachable seen silo SHALL render with its last-seen time
and its last-known class rather than being probed or dropped.

#### Scenario: the probe decides
- **WHEN** the app holds a passkey for a silo and probes it, then probes with a passkey the silo
  does not accept
- **THEN** the silo classifies as seen-with-access on the first probe and seen-without-access on
  the second

#### Scenario: unreachable is last-known, not unknown
- **WHEN** a seen silo stops answering
- **THEN** it renders as seen with its last-seen time and its last-known access state

Pinned by: nothing yet.

### Requirement: The setup flow mints the passkey, shows it once, and installs it
For a bootstrap silo, SiloAdmin SHALL generate a random 128-bit passkey, render it for a human
to transcribe, and display it exactly once with an offer to copy it, before sending
`POST /v1/setup` with it and an optional name. On success it SHALL store the passkey in its
Keychain keyed by the silo's `ServerID`, record the silo in its registry, and reclassify it as
seen, has access. The passkey SHALL NOT be logged, written to files by the app, or displayed in
full ever again. A `410` reply SHALL end the flow, discard the passkey minted for that attempt,
and leave the silo classified by its probe result — a retry whose earlier attempt landed keeps the
earlier passkey, which the probe resolves honestly.

#### Scenario: setup from the chair
- **WHEN** the operator confirms the setup sheet for a bootstrap silo
- **THEN** the app mints the passkey, the setup call succeeds, the passkey is in the Keychain
  under the silo's ServerID, and the silo shows as seen, has access

#### Scenario: someone else got there first
- **WHEN** the setup call is refused with 410
- **THEN** the passkey minted for that attempt is discarded, any passkey the Keychain already
  holds for the ServerID stays, and the silo is classified by what its probe says

Pinned by: nothing yet.

### Requirement: Claiming is entering the passkey, and the probe is the verdict
For an unseen silo, and for a seen silo with no access, SiloAdmin SHALL offer to claim it with a
passkey the operator supplies. The supplied passkey SHALL be verified by the probe before it is
stored; a passing probe SHALL store the passkey in the Keychain, merge the silo into the
registry, and classify it seen, has access, and a refused probe SHALL store nothing.

#### Scenario: wrong passkey, nothing kept
- **WHEN** the operator claims a silo with a passkey the silo refuses
- **THEN** the Keychain and the registry hold no passkey for that ServerID and the silo stays
  seen, no access

Pinned by: nothing yet.
