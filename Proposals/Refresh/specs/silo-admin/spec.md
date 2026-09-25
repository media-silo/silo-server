<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

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

Pinned by: nothing yet.

## ADDED Requirements

### Requirement: The console keeps itself current
SiloAdmin SHALL refresh on its own — when its window appears, on a steady interval, and
whenever the app returns to the fore — and SHALL offer no manual refresh control: freshness is
the app's job, not the operator's. One sweep SHALL NOT overlap another: a refresh asked for
while one is in flight SHALL join it rather than starting anew, so the silos are asked once no
matter how many voices asked. The interval governs how fast truth arrives; classification
alone decides what truth is shown.

#### Scenario: two calls, one sweep
- **WHEN** a refresh is asked for while one is still in flight
- **THEN** the second call joins the first's sweep, and the silos are asked once

Pinned by: nothing yet.

### Requirement: A silo the operator cannot use is announced, and why
When the selected silo is unreachable, its detail SHALL render dimmed and non-interactive under
a banner saying the silo is currently unreachable, and SHALL restore itself — dim and banner
both — when the silo answers again; the sidebar and each row's acts SHALL stay live throughout,
forgetting an unreachable silo being precisely the act that moment calls for. When the probe
refuses a passkey this Mac holds, the console SHALL name the refusal — the stored passkey is no
longer accepted — rather than rendering plain no-access, on the row and, for the selected silo,
in a banner of its own, with the claim act still on offer.

#### Scenario: the selected silo goes quiet
- **WHEN** the silo the operator is looking at flips to unreachable
- **THEN** its detail dims behind a "currently unreachable" banner, and the row's acts — forget
  included — stay live

#### Scenario: a held passkey stops fitting
- **WHEN** the probe refuses the stored passkey of the selected silo
- **THEN** the console says the stored passkey is no longer accepted, with claim still on offer

Pinned by: nothing yet.
