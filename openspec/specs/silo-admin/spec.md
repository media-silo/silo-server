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

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`twoCallsOneSweep`).

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

Pinned by: nothing yet (the banners are shell rendering, and the shell has no test target).

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

### Requirement: The console shows a silo's settings, and changes what routes may change
For a silo classified with access, SiloAdmin SHALL show the settings `GET /v1/settings` reports. The
name, the embedded node and advertising SHALL be editable through `PATCH /v1/settings`; the
libraries SHALL be shown with their paths, read-only, each with the ruleset that is its standard, which
the operator MAY name or clear through `PUT /v1/libraries/{library}/ruleset`; and the `silo.json` settings and the state
directory SHALL be shown read-only, as facts of the silo's machine. A refusal from the silo SHALL be shown in words, naming the reason the silo gave.

#### Scenario: the machine's facts are read-only
- **WHEN** the operator opens a silo's settings
- **THEN** its host, port and state directory are shown and cannot be edited, and its name,
  embedded node and advertising can

#### Scenario: a library's standard named
- **WHEN** the operator names `household` as a library's standard from the console
- **THEN** the route is sent, and the library shows the standard the silo answered with

#### Scenario: an edit applies without a restart
- **WHEN** the operator turns the embedded node on from the console
- **THEN** the patch is sent, and the settings shown are the ones the silo answered with

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`settingsAreAskedWithTheHeldPasskey`,
`aSettingsChangeSendsOnlyWhatChangedAndARenameIsRendered`, `aLibrarysStandardIsNamedFromTheConsole`),
`Tests/SiloAdminTests/ConsoleModelTests.swift` (`aLibrarysStandardShowsWhatTheSiloAnswered`), which pin
the engine and the model the pane is drawn from; the pane itself is pinned by nothing yet.

### Requirement: The console shows a silo's rulesets, their branches and versions, and the silo's reading of each
For a silo classified with access, SiloAdmin SHALL show each ruleset the silo holds, and for a ruleset
its branches — each with its base, its head, the standard version it is up to date with, and whether it
has been promoted — and its versions on each, with the number of placed presentations each made. For a
version it SHALL show the document as the silo stored it, comments and all, and beside it the silo's
reading: the extraction policy, the rules grouped by scope in document order within each, each by the
name a recipe calls it by with its conditions and action, and the outputs. A scope whose last rule has
conditions SHALL be marked as having no catch-all. The console SHALL draw the reading from the silo
and SHALL NOT read a ruleset's XML itself. The section SHALL keep itself current as the rest of the
console does.

#### Scenario: a ruleset opened
- **WHEN** the operator opens a ruleset whose standard's head is version 3
- **THEN** version 3's document is shown as stored, beside the silo's reading of it, and the branches
  and their versions can be chosen

#### Scenario: a scope that can stop an application
- **WHEN** a version's audio rules all have conditions
- **THEN** the audio scope is marked as having no catch-all

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aRulesetOpensAtItsStandardsHeadBesideTheSilosReading`), `Tests/SiloAdminTests/ConsoleModelTests.swift`
(`theRulesetsSectionKeepsItselfCurrent`), `Tests/SiloTests/ServerTests.swift`
(`theConsolesTypesReadTheSilosAnswers`).

### Requirement: The console shows a library's out-of-date presentations
For each library of a silo classified with access, SiloAdmin SHALL show its out-of-date presentations
as the silo's report gives them — each with its container and item, the stack that made it and the
stack it was checked against, the streams that would change from what to what, and whether every
source of its binding has a copy — and how many of the library's presentations are still to be
checked. It SHALL make nothing again.

#### Scenario: a check under way
- **WHEN** the silo's background check has twelve presentations still to check in a library
- **THEN** the library shows the out-of-date presentations found so far, and says twelve are still to
  be checked

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`eachLibrarysOutOfDateIsReadWithWhatIsStillToCheck`), `Tests/SiloTests/CheckTests.swift`
(`aDraftsImpactIsWhatTheCheckFindsOnceItIsInForce`).

### Requirement: A draft is edited as text and checked by the silo as it is typed
SiloAdmin SHALL edit a ruleset as its document's text, starting a draft from a version on screen — its
base — from a copy of any version, or from the starter: the default extraction policy, a condition-less
copy rule for each scope, and the default output. A copy's `name` attribute SHALL be changed to the new
name as an edit shown in the text. As the operator types, and a moment after they stop, the console
SHALL check the draft with the silo and show the silo's reading in place of the base's, or the silo's
refusal in its words. A draft SHALL live in the console until it is stored or discarded, and SHALL
survive its section being closed and the section's refresh.

#### Scenario: a mistyped fact is refused before the store
- **WHEN** the operator types `<when fact="subtitle.forcd" is="true"/>` into a draft
- **THEN** the reading gives way to the silo's refusal, and nothing has been stored

Pinned by: `Tests/SiloAdminKitTests/DraftTests.swift` (`aChangeIsBasedOnTheVersionItWasMadeFrom`,
`aCopyIsRenamedAsAnEditInTheText`, `theStarterDecidesEveryStreamWithTheDefaults`),
`Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aMistypedFactIsRefusedBeforeTheStore`),
`Tests/SiloAdminTests/ConsoleModelTests.swift` (`aDraftIsCheckedAsItIsTypedAndOutlivesItsSection`).

### Requirement: Nothing is stored before the draft's difference and impact are shown
Before a draft can be stored, SiloAdmin SHALL show its text's difference from its base and its impact
as the silo reports it — every placed presentation the draft would make differently, and how — and
SHALL make none of them again.

#### Scenario: a bitrate lowered
- **WHEN** a draft lowers the commentary bitrate of a ruleset whose version made 41 placed
  presentations, 12 of them with a commentary
- **THEN** before the store the console shows the one line that changed and the 12, each with its
  commentary's encode before and after

Pinned by: `Tests/SiloAdminTests/ConsoleModelTests.swift`
(`aReviewShowsTheChangeAndImpactAndALandedVersionKeepsTheDraft`), `Tests/SiloAdminKitTests/DraftTests.swift`
(`aChangeIsBasedOnTheVersionItWasMadeFrom`).

### Requirement: A store names its base, and a refusal keeps the draft
SiloAdmin SHALL store a draft to its base's branch, to another branch, or to a new branch started from
its base when the base is on the standard, and SHALL send `basedOn`, the head of the branch it is
stored to. A 201 SHALL show the new version and end the draft. A 409 SHALL keep the draft and show the
version that landed and how it differs from the base, and SHALL offer to re-base the draft on it or
discard it; the console SHALL NOT merge. Going back to an earlier version SHALL be a store of its
document as a draft based on the head.

#### Scenario: someone stored first
- **WHEN** the operator stores a draft based on version 3 and version 4 has landed from another Mac
- **THEN** the draft is kept, version 4 and its difference from 3 are shown, and the operator may
  re-base the draft on 4 or discard it

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aStoreNamesItsBaseAndAVersionThatLandedFirstKeepsTheDraft`, `aDraftIsStoredOnANewBranchStartedFromItsBase`),
`Tests/SiloAdminKitTests/DraftTests.swift` (`goingBackIsAnEarlierDocumentBasedOnTheHead`),
`Tests/SiloAdminTests/ConsoleModelTests.swift` (`aReviewShowsTheChangeAndImpactAndALandedVersionKeepsTheDraft`).

### Requirement: A branch is promoted from the console with its impact beside it
SiloAdmin SHALL offer to promote an open branch, showing beside it what promoting would put out of date
as the silo's branch impact gives it. A refusal SHALL be shown with the standard versions the branch
has not taken in and how they differ from its base, and the console SHALL let the operator store a
draft on the branch declaring, with `upToDateWith`, the standard's head it takes in.

#### Scenario: a promotion over the standard's work
- **WHEN** the operator promotes a branch the standard has gained version 9 since
- **THEN** the refusal names version 9 and shows how it differs from the branch's base, and promotion
  is offered again once a draft taking it in is stored on the branch

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aRefusedPromotionNamesWhatTheBranchHasNotTakenIn`), `Tests/SiloAdminTests/ConsoleModelTests.swift`
(`aRefusedPromotionLeadsToADraftTakingTheStandardIn`).
