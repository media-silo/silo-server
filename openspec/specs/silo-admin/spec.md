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
SHALL drop its row from the rendered list, and SHALL delete every draft this Mac keeps for it. If the silo answers again afterwards, it SHALL
arrive as never met — a fresh registry entry, no stored passkey, no last-known access.

#### Scenario: forget purges the registry and the passkey
- **WHEN** the operator forgets an unreachable silo
- **THEN** the Keychain holds no passkey for it, the registry holds no entry for it, and its row
  leaves the rendered list

#### Scenario: a rediscovery restarts history
- **WHEN** a forgotten silo answers a browse again
- **THEN** it merges into the registry as a fresh contact with no passkey and no last-known
  access, and classifies without-access

#### Scenario: forgetting takes the drafts
- **WHEN** the operator forgets an unreachable silo for which this Mac keeps two drafts
- **THEN** both drafts are deleted, and a rediscovery of the silo lists none

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
name, the embedded node and advertising SHALL be editable through `PATCH /v1/settings`; and the
`silo.json` settings and the state directory SHALL be shown read-only, as facts of the silo's
machine. The libraries SHALL be shown apart from the settings, in a section of their own beside the
settings, the rulesets and the out-of-date presentations, as the libraries requirement below sets
out. A refusal from the silo SHALL be shown in words, naming the reason the silo gave.

#### Scenario: the machine's facts are read-only
- **WHEN** the operator opens a silo's settings
- **THEN** its host, port and state directory are shown and cannot be edited, and its name,
  embedded node and advertising can

#### Scenario: an edit applies without a restart
- **WHEN** the operator turns the embedded node on from the console
- **THEN** the patch is sent, and the settings shown are the ones the silo answered with

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`settingsAreAskedWithTheHeldPasskey`,
`aSettingsChangeSendsOnlyWhatChangedAndARenameIsRendered`), which pins the engine; the pane itself
is pinned by nothing yet.

### Requirement: The console shows a silo's rulesets, their branches and versions, and the silo's reading of each
For a silo classified with access, SiloAdmin SHALL show each ruleset the silo holds, and for a ruleset
its branches — each with its base, its head, the standard version it is up to date with, and whether it
has been promoted — and its versions on each, with the number of placed presentations each made. For a
version it SHALL show the document as the silo stored it, comments and all, and beside it the silo's
reading: the rules grouped by scope in document order within each, each by the
name a recipe calls it by with its conditions and action, and the outputs. A scope whose last rule has
conditions SHALL be marked as having no catch-all. A version's reading SHALL be the silo's. The section SHALL keep itself current as the rest of the
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
base — from a copy of any version, or from the starter: a condition-less copy
rule for each scope and the default output. A copy's `name` attribute SHALL be changed to the new
name as an edit shown in the text. As the operator types, and a moment after they stop, the console
SHALL check the draft with the silo and show the silo's reading in place of the base's, or the silo's
refusal in its words. A draft SHALL be the console's: kept on this Mac, for the silo by its
`ServerID`, as its text, its base and the standard version it declares it takes in, and saved there a
moment after the operator stops editing, so that it outlives its section, the section's refresh and the
app. Any number of drafts MAY be kept. SiloAdmin SHALL list each under the branch of its base, or under
its name for a ruleset the silo holds no version of, and SHALL mark a draft whose base is no longer its
branch's head as behind. A draft SHALL end only when it is stored or discarded, or its silo forgotten.
The silo SHALL hold no draft.

#### Scenario: a mistyped fact is refused before the store
- **WHEN** the operator types `<when fact="subtitle.forcd" is="true"/>` into a draft
- **THEN** the reading gives way to the silo's refusal, and nothing has been stored

#### Scenario: a draft left overnight
- **WHEN** the operator edits a draft based on the standard's version 3, quits the app, and opens it
  again
- **THEN** the draft is listed under the standard, with the edit

#### Scenario: a draft that is behind
- **WHEN** a draft is based on version 3 of the standard, and version 4 is stored on the standard from
  another Mac
- **THEN** the draft is listed as behind, before the operator tries to store it

Pinned by: `Tests/SiloAdminKitTests/DraftTests.swift` (`aChangeIsBasedOnTheVersionItWasMadeFrom`,
`aCopyIsRenamedAsAnEditInTheText`, `theStarterDecidesEveryStreamWithTheDefaults`),
`Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aMistypedFactIsRefusedBeforeTheStore`),
`Tests/SiloAdminTests/ConsoleModelTests.swift` (`aDraftIsCheckedAsItIsTypedAndOutlivesItsSection`,
`aDraftIsKeptOnThisMacListedUnderItsBranchAndMarkedBehind`), `Tests/SiloAdminKitTests/DraftTests.swift`
(`draftsOutliveTheStoreThatKeptThem`, `aDraftIsBehindOnceItsBranchHasMoved`).

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

### Requirement: A draft is shown parsed or as its text
SiloAdmin SHALL show a draft in two views of the one text, toggled: the text, editable, and the draft
parsed — the rules by scope in the order that decides, each with its name, conditions and action, and
the outputs. The console SHALL parse the draft itself, with the reader the silo runs. When the text
cannot be read, the parsed view SHALL show the reader's refusal, with the line and column for XML that
is not well formed.

#### Scenario: text that is not well formed
- **WHEN** the operator deletes the `>` that closes a rule's opening tag
- **THEN** the parsed view gives way to the reader's refusal, naming the line and column where reading
  stopped, and nothing has been stored

Pinned by: `Tests/SiloAdminKitTests/DraftTests.swift` (`aDraftIsReadByTheConsoleWithTheSilosReader`).

### Requirement: A draft is edited in a form built from the rule language
SiloAdmin SHALL edit a draft in a form: rules added, edited, deleted, and dragged by a handle to
reorder within their scope; outputs added, edited and deleted. Each rule SHALL read as its clauses:
IF its first condition and AND each other, then THEN its action, an encode followed by WHERE its first
setting and AND each other. A rule after the first of its scope SHALL read OTHERWISE IF in place of IF,
and a rule with no condition SHALL read ALWAYS its action when it is its scope's first rule and
OTHERWISE its action after another. A rule's facts SHALL be named without its scope's prefix, and its
id shown only when it has one. A condition's fact SHALL be chosen from the rule language's facts,
offering only the tests the fact takes, named in words, and, where the fact's values are a closed set,
only those values, or, for `kind`, the types SmdKit names, `episode` and `movie` first and then the
extra types, offered beside a field that takes any; a `one of` SHALL take each value in a field of its own. An action SHALL be copy,
drop, or an encode with its settings as fields, its codec offered by the name a condition on the codec
uses, written as the encoder `ffmpeg` lists for it, and a new encode starting with a codec of the
rule's scope. An encode SHALL offer only the settings its codec takes — a video encode its preset,
CRF, bitrate and pixel format, an audio encode its channels and, unless its codec is lossless, its
bitrate, and a subtitle encode none — and SHALL write no other. Every change SHALL be made by splicing the draft's text, so the text view shows exactly
what changed. While the text cannot be read, the form SHALL show the reader's refusal and make no
change.

#### Scenario: a rule moved in the form
- **WHEN** the operator drags the commentary rule above the lossless rule
- **THEN** the text shows the rule moved with its comment, and no other difference

#### Scenario: a fact's tests
- **WHEN** the operator adds a condition on `audio.channels`
- **THEN** the form offers the seven tests, and for `audio.role` only `is`, `ne` and `in`, with its
  roles as the values

#### Scenario: a rule read in the form
- **WHEN** a video rule encodes with `libx265` and `crf` 20 when `video.interlaced` is `true`, and the
  scope's next rule drops when `video.width` is below 720
- **THEN** the first reads IF `interlaced is true` THEN `encode` WHERE `codec is hevc` AND `crf is 20`,
  and the second OTHERWISE IF `width < 720` THEN `drop`

#### Scenario: a rule with no condition
- **WHEN** a subtitle rule copies with no condition
- **THEN** it reads ALWAYS `copy` as its scope's first rule, and OTHERWISE `copy` after another

#### Scenario: an item's kind
- **WHEN** the operator adds a condition on `kind`
- **THEN** the form offers `episode`, `movie`, and then the extra types from `featurette` to
  `themeVideo`, and takes a type it does not offer

#### Scenario: tests named in words
- **WHEN** the operator chooses a condition's test
- **THEN** `ne` is offered as `is not`, `in` as `one of`, and `lt`, `le`, `gt` and `ge` as `<`, `≤`,
  `>` and `≥`

#### Scenario: an encode's codec
- **WHEN** the operator makes a new video rule an encode and chooses the codec `hevc`
- **THEN** its codec starts as `h264`, and the document's encode names the encoder `libx265`

#### Scenario: an encode's settings
- **WHEN** the operator makes an audio rule an encode with `aac`, then changes its codec to `flac`
- **THEN** the form offers its bitrate and channels, then only its channels, and the document's
  encode carries no bitrate

Pinned by: `Tests/SiloKitTests/RulesetTextTests.swift` (`aMoveLeavesEverythingElseAsItWas`, for the
splice a drag makes, and `aFactOffersTheTestsAndValuesItTakes`, for what a condition offers), and
`Tests/SiloAdminKitTests/RuleSentencesTests.swift` (`aRuleReadsAsIfAndThenWhere`,
`aLaterRuleIsReachedOnlyOtherwise`, `testsAreNamedInWordsAndFactsWithoutTheirScope`,
`anEncodeIsOfferedByCodecAndWritesItsEncoder`, `anEncodeTakesTheSettingsItsCodecHas` and
`aKindIsOfferedFromTheTypesSmdKitNames`); the form itself is shell rendering, and the shell has
no test target.

### Requirement: A branch's version is tried on chosen bindings, and each trial compared with what is placed
From a version on a branch, SiloAdmin SHALL let the operator choose bindings to try it on, offering
first the bindings of the presentations its impact on the standard lists, and any other by its id, and
SHALL apply the branch at that version to each and make a trial job of each recipe the application
makes, telling a binding the version cannot be applied to in the silo's words. It SHALL show each trial
job's progress, and for a tried trial, beside the presentation its binding placed for the same output
when the branch's impact lists it, each stream's decision in the placed recipe and in the trial's, and
both files to play. It SHALL place nothing.

#### Scenario: three trials of a lowered bitrate
- **WHEN** the operator tries a branch's version that lowers the commentary bitrate on three bindings
  its impact lists, and the trials are encoded
- **THEN** each trial shows its commentary at the new bitrate beside the placed presentation's at the
  old, and nothing has been placed

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aBranchsVersionIsTriedOnChosenBindingsAndComparedWithWhatIsPlaced`); the sheet and the panel are
shell rendering, and the shell has no test target.

### Requirement: The console shows a silo's libraries, and adds and removes them within the roots
For a silo classified with access, SiloAdmin SHALL show each library with its path, whether it is
available, when it was last walked, and the findings of that walk, and with the ruleset that is its
standard, which the operator MAY name or clear through `PUT /v1/libraries/{library}/ruleset`. The
section SHALL read the libraries and their walks again at the console's cadence while it is open.
It SHALL add a library through `POST /v1/libraries`, offering the silo's library roots as the places
to choose within, and when the roots are empty SHALL say that the silo has none rather than offer a
path the silo will refuse. While the operator names a folder, it SHALL ask
`POST /v1/libraries/check` and show the path, in a sentence saying whether a library will be created
there, with the part that exists told apart from the part that does not: the missing folders as
refused while nothing asks for them to be made, and as to be made once the operator asks and the
silo would make them, saying how many; a path whose folders all exist SHALL be said to exist. Any
other refusal of the path SHALL be given in that sentence in the silo's words, and a refusal of the
name, which leaves the path good, SHALL be shown apart from it in the silo's words. When folders are missing it SHALL offer
to make them, and SHALL send `create` only when the operator has asked for them to be made. It SHALL
remove a library through `DELETE /v1/libraries/{library}`, and a refusal SHALL be shown in words.
The console SHALL offer no way to start a walk.

#### Scenario: an unavailable library is shown as such
- **WHEN** the operator opens the libraries of a silo whose `films` folder is missing
- **THEN** `films` is shown unavailable, with when it was last walked

#### Scenario: a library's standard named
- **WHEN** the operator names `household` as a library's standard from the console
- **THEN** the route is sent, and the library shows the standard the silo answered with

#### Scenario: empty roots, no picker
- **WHEN** the operator goes to add a library to a silo whose library roots are an empty list
- **THEN** the console says the silo has no library roots, rather than offering a path

#### Scenario: missing folders shown, and made when asked
- **WHEN** the operator names a folder within a root, two of whose folders do not exist
- **THEN** the console shows the path with both apart from the part that exists, says a library
  cannot be created there because the two folders do not exist, and once the operator asks for them
  to be made says a library will be created there and the two folders made; the addition sends
  `create` only then

#### Scenario: a name already taken leaves the path good
- **WHEN** the operator names a folder that exists, for a library whose name the silo already has
- **THEN** the console says a library will be created at the path, which exists, and shows apart from
  it the silo's refusal of the name

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`librariesAreAddedAndRemovedFromTheConsole`,
`aLibrarysStandardIsNamedFromTheConsole`, `aLibrarysPathIsCheckedAndItsFoldersMadeFromTheConsole`),
`Tests/SiloAdminTests/ConsoleModelTests.swift` (`anUnavailableLibraryIsShownWithItsLastWalk`,
`theLibrariesSectionKeepsItselfCurrent`, `aLibrarysStandardShowsWhatTheSiloAnswered`,
`withTheRootsEmptiedTheConsoleSaysSoAndShowsTheRefusal`), `Tests/SiloTests/ServerTests.swift`
(`theConsolesTypesReadTheSilosAnswers`), which pin the engine, the model the pane is drawn from and
the console's types against the silo's answers; the pane itself is pinned by nothing yet.

### Requirement: The console shows each library's containers, and a container as its library's sidecar says it
For a silo classified with access, SiloAdmin SHALL show each library's containers as a tree
beneath the library, in the section that shows the libraries, from the containers at the top of
the library down through the children each sidecar names, listed and unlisted alike, read from
the library's own container routes. A container SHALL be
shown as the library's sidecar says it: its own fields, its alternatives and features, its
sequences and extras with each item's presentations in that library — by display name, profile,
alternative and file — and the items that have none, its children, its artwork, and the
findings the library's last walk reported on its sidecar. The console SHALL add no reading of
its own. The section SHALL read each library's containers again at the console's cadence while
it is open, as it reads the libraries and their walks.

#### Scenario: a season with gaps
- **WHEN** the operator opens a season of which the library holds presentations of four
  episodes out of six
- **THEN** the season shows six episodes, four with their presentations and two with none

#### Scenario: a container the walk found wrong
- **WHEN** the library's last walk reported an error on a container's sidecar
- **THEN** the container shows the error in the walk's words

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainersAreBrowsedAndEditedFromTheConsole`), `Tests/SiloAdminTests/ConsoleModelTests.swift`
(`theLibrariesSectionKeepsItselfCurrent`), `Tests/SiloTests/ServerTests.swift`
(`theConsolesTypesReadTheSilosAnswers`). The browser itself and its tree are pinned by nothing yet,
as the rest of the shell is.

### Requirement: A container's own fields are edited in a form, as a draft kept on this Mac
SiloAdmin SHALL edit a container's own fields in a form: its title, year, type, type label, outline,
whether it is listed, and its external references; and its alternatives, features, sequences, items
and extras, each added, edited, removed and reordered. An outline attributed to a provider SHALL be
shown with its attribution: editing the text SHALL keep the attribution, removing the outline SHALL
remove it, and the operator MAY remove the attribution alone, which the console SHALL confirm with
them first. A draft SHALL keep its attributions of the container's own fields, and its store SHALL
carry them. An edit SHALL be a draft, kept on this Mac for the silo by its `ServerID`, the library
and the container, with the digest of the sidecar it was based on, saved a moment after the operator
stops editing so that it outlives the section, its refresh and the app. A draft whose library's
sidecar has changed since SHALL be marked behind. As the operator types, and a moment after they
stop, the console SHALL ask the silo for a dry run of the draft and show its findings. Before a
draft is stored, the console SHALL show its document's difference from the sidecar it was based on,
and the findings. A store SHALL name its base; a 409 SHALL keep the draft, show the sidecar that
landed and how it differs from the base, and offer to re-base the draft on it or discard it, and the
console SHALL NOT merge; a 422 SHALL keep the draft and show the findings that refused it. A draft
SHALL end only when it is stored or discarded, or its silo forgotten.

#### Scenario: an edit left overnight
- **WHEN** the operator corrects a container's year, quits the app before storing, and opens
  it again
- **THEN** the draft is there for the container, with the correction

#### Scenario: someone edited first
- **WHEN** the operator stores a draft and the container's sidecar was changed from another Mac
  after the draft was based on it
- **THEN** the draft is kept, the sidecar that landed and its difference from the base are
  shown, and the operator may re-base the draft or discard it

#### Scenario: an edit the silo refuses
- **WHEN** the operator removes an alternative two of the library's presentations are of
- **THEN** the dry run's findings name both presentations before anything is stored

#### Scenario: an attributed outline reworded
- **WHEN** the operator rewords an outline the library's sidecar attributes to TMDb, and stores the
  draft
- **THEN** the sidecar holds the reworded outline, still attributed to TMDb

#### Scenario: an attribution removed alone
- **WHEN** the operator removes an outline's attribution, confirms it, and stores the draft
- **THEN** the sidecar holds the outline as it was, with no attribution

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainersAreBrowsedAndEditedFromTheConsole`,
`anAttributedOutlineIsKeptThroughAnEdit`). The form, the saving a moment after the
operator stops, the dry run as they type and the review are pinned by nothing yet, as the rest of
the shell is.

### Requirement: A container's artwork is shown, put and removed from the console
SiloAdmin SHALL show, for a container, each artwork kind its folder holds, and SHALL let the
operator put an image as a kind — dropped onto it, or chosen — and remove a kind, through the
library's artwork routes. For a container whose TMDb record the console finds, as its differences
from TMDb find it, SiloAdmin SHALL let the operator browse TMDb's images for the record — its posters
for `poster`, its backdrops for `fanart` and its logos for `logo` — and put one, with its
attribution to `tmdb` and the record's id. A kind whose image is attributed SHALL be shown with its
attribution, and an image dropped or chosen from this Mac SHALL be put with none, removing any the
kind had. A refusal SHALL be shown in words.

#### Scenario: a poster dropped
- **WHEN** the operator drops a JPEG onto a container's poster
- **THEN** the image is put, and the container shows the poster the silo serves

#### Scenario: a poster taken from TMDb
- **WHEN** the operator puts one of TMDb's posters for a film the library holds by its TMDb
  reference
- **THEN** the container shows the poster the silo serves, credited to TMDb

#### Scenario: a TMDb poster replaced with the operator's own
- **WHEN** the operator drops a JPEG onto a poster credited to TMDb
- **THEN** the container shows the new poster, credited to no one

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainersAreBrowsedAndEditedFromTheConsole`,
`artworkIsTakenFromTMDbWithItsAttribution`). Dropping and choosing an image are
pinned by nothing yet, as the rest of the shell is.

### Requirement: The console shows the moves an edit makes, and lays a library out again
Before a container draft is stored, SiloAdmin's review SHALL list the folders the silo's dry run
says the store would move, `from` and `to`. A library's detail SHALL offer to lay the library out
again: the console SHALL ask the silo for the layout's dry run, show its moves and findings, and
apply them when the operator confirms, showing any rename that failed in the silo's words.

#### Scenario: a title edit reviewed
- **WHEN** the operator reviews an edit correcting a film's year
- **THEN** the review lists the film's folder moving to the name with the corrected year

#### Scenario: a library laid out again
- **WHEN** the operator lays out a library whose folders were renamed by hand
- **THEN** the console lists each folder's move before anything moves, and after applying, the library's last walk warns of none of them

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aLibraryIsLaidOutFromTheConsole`).
The review's list and the layout sheet are pinned by nothing yet, as the rest of the shell is.

### Requirement: The console reads smddb from a clone on this Mac, and never commits to it
SiloAdmin's settings SHALL name a folder on this Mac as a clone of smddb's data repository, and
the console SHALL read it through SmdKit's `LocalRepository`, reading it again when the app becomes
active and when the operator asks. The console SHALL NOT clone, pull, commit or push. With no
folder named, or one whose containers cannot be read, the console's smddb actions SHALL be
unavailable and SHALL say why. For each container a library holds, the browser SHALL say whether
the clone holds the same id and, when it does, whether the library's own fields match smddb's
record or differ from it, comparing the two documents without asking the silo.

#### Scenario: a container corrected in the library
- **WHEN** the operator has corrected a container's year in a library, and the clone holds the
  container with the old year
- **THEN** the browser says the library's container differs from smddb's record

#### Scenario: no clone named
- **WHEN** the console's settings name no clone
- **THEN** the smddb actions are unavailable, and say that no clone is named

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainersStandAgainstSmddb`). The setting and the reading again are pinned by nothing
yet, as the rest of the shell is.

### Requirement: A container is imported from smddb into a library, beneath the nearest ancestor the library holds
SiloAdmin SHALL let the operator search the clone's containers by title and by provider id, pick a
container, and choose which of its descendants to bring, all of them chosen to begin with and those
the library already holds shown and not choosable. The console SHALL take as the parent the nearest
of the container's ancestors in smddb that the library holds, or none, and SHALL ask the silo to
make every container from just below the parent down to the ones chosen, first as a dry run whose
writes and findings it shows, and then, when the operator confirms, for real. When the parent's
sidecar does not name the next container down, the console SHALL offer to bring the parent's own
fields from smddb as an edit draft, stored as any edit is. A container the library already holds
SHALL NOT be imported: the console SHALL offer smddb's record as an edit draft of the library's
container, based on the sidecar the browser read.

#### Scenario: a season whose series the library holds
- **WHEN** the operator imports a season from smddb into a library that holds its series, whose
  sidecar names the season
- **THEN** the console creates the season and its chosen serials beneath the series, and the
  browser shows them with no presentations

#### Scenario: a series sidecar older than smddb's record
- **WHEN** the operator imports a season whose series the library holds, and the library's series
  sidecar does not name the season
- **THEN** the dry run's refusal is shown, and the console offers an edit draft of the series with
  smddb's own fields

#### Scenario: a container the library holds
- **WHEN** the operator picks in smddb a container the library already holds
- **THEN** the console offers an edit draft of the library's container whose document is smddb's,
  and imports nothing

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aContainerIsImportedFromSmddbBeneathTheNearestHeldAncestor`). The search and the choosing are
pinned by nothing yet, as the rest of the shell is.

### Requirement: A container is created in the console with a provisional id
SiloAdmin SHALL create a container in the container form, over an empty container whose id is the
one the clone's `provisionalID()` answers, at the top of a library or as a child of a container
the library holds, at a sequence and position of the parent's the operator chooses. A new container
SHALL be a draft kept on this Mac, as an edit draft is, until it is created or discarded. Creating
a child SHALL first store an edit of the parent naming the new child, based on the parent's
sidecar, and then ask the silo to make the child. A refusal of either SHALL be shown in words and
SHALL keep the new container's draft.

#### Scenario: a container created at the top of a library
- **WHEN** the operator creates a film in a library, and stores it
- **THEN** the library holds the film with an id the clone has no file for, and no presentations

#### Scenario: a season created beneath a series
- **WHEN** the operator creates a season as the next entry of a series' seasons
- **THEN** the series' sidecar names the season, and the library holds the season beneath it

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aContainerIsCreatedWithAProvisionalID`).
The form and its drafts are pinned by nothing yet, as the rest of the shell is.

### Requirement: A library's container is proposed to smddb from its sidecar
SiloAdmin SHALL propose a library's container to smddb by contributing, through the clone, the
container's own fields as that library's sidecar says them, as a repository document. In each
container it contributes, a field the library's sidecar attributes to a provider SHALL take instead
the value the clone's record of the same id holds, or none when the clone has no record, and the
console SHALL list each field it left out with its provider. Before it contributes, the console
SHALL show the document's difference, as it will be contributed, from the clone's record of the same
id, or say the clone has none, and SHALL offer with it, chosen, the containers it names that the
clone does not hold, as children beneath it or through a ref, from the library's sidecars; one the
library does not hold either SHALL be shown as the reason the contribution would be refused. After
it contributes, the console SHALL say which files it wrote in the clone. The library's sidecar SHALL
NOT change, and the document SHALL carry none of the library's presentations, children's paths or
rules.

#### Scenario: a container created in the console proposed
- **WHEN** the operator proposes a container that was created in the console and is not in the
  clone
- **THEN** the console shows that the clone has no record of it, writes its file into the clone's
  containers, and says which file it wrote

#### Scenario: a correction proposed
- **WHEN** the operator proposes a container whose year was corrected in the library
- **THEN** the difference shown is the year, and the clone's file carries the corrected year and
  none of the library's presentations

#### Scenario: an attributed outline proposed
- **WHEN** the operator proposes a container whose outline the library attributes to TMDb, and the
  clone has no record of it
- **THEN** the review lists the outline as left out, attributed to TMDb, and the file written into
  the clone carries no outline

#### Scenario: an attributed outline over smddb's own
- **WHEN** the operator proposes a container whose outline the library attributes to TMDb, and the
  clone's record of it has an outline of its own
- **THEN** the difference shown has no change to the outline, and the clone's file keeps its own
  outline

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainerIsProposedToSmddb`,
`anAttributedFieldIsLeftOutOfAContribution`). The review before contributing is pinned by nothing yet,
as the rest of the shell is.

### Requirement: The console reads TMDb with a token kept on this Mac, and credits it
SiloAdmin's settings SHALL take a TMDb read access token, kept in this Mac's keychain and never
written to a file by the app, and a language for TMDb's answers, the Mac's by default. The console
SHALL reach TMDb itself. The silo SHALL NOT be given the token, and SHALL NOT be asked to reach TMDb.
With no token, or one TMDb refuses, the console's TMDb actions SHALL be unavailable and SHALL say
why. The settings SHALL carry TMDb's logo and the notice that the product uses the TMDb API but is
not endorsed or certified by TMDb. Wherever the console shows something it read from TMDb, it SHALL
mark it as TMDb's.

#### Scenario: no token given
- **WHEN** the console's settings hold no TMDb token
- **THEN** the TMDb actions are unavailable, and say that no token is given

#### Scenario: a token TMDb refuses
- **WHEN** the console's TMDb token is one TMDb answers as unauthorized
- **THEN** the TMDb actions are unavailable, and say that TMDb refused the token

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`tmdbIsUnavailableWithoutAToken`). The
setting, the keychain and the credit are pinned by nothing yet, as the rest of the shell is.

### Requirement: A container is drafted from TMDb's record, and shaped before it is created
SiloAdmin SHALL search TMDb's movies and series by title. A container's `tmdb` reference SHALL be
read by its type: on a `movie` a movie's id, on a `collection` a collection's, on a `series` a
series', and on a `season` a season's. An entry's `tmdb` references SHALL be read only against a
reading, as the ids of the reading's episodes they match, since one entry may carry ids from more
than one of TMDb's ranges. Picking a record whose reference the
clone holds on a container of the same kind SHALL offer that container's import from smddb, and
SHALL NOT draft it. Picking one whose reference a container of the library carries SHALL NOT draft
it, and the console SHALL say the library holds it. Otherwise the console SHALL read the record as
containers: a movie as a `movie`; a series as a `series` with a `season` child for each of TMDb's
seasons but season 0, whose episodes are the series' specials; a season as a `season` holding each of its episodes as an entry, in TMDb's order; a
collection as a `collection` with each of its movies as a child; and, when the operator chooses one
of a series' episode groups as its shape, each group as a child container of the type the operator
picks, holding the group's episodes as entries in the group's order. Each container SHALL carry the
record's title, its year where its type has one, a `tmdb` reference, and a reference for each other
provider's id TMDb holds for it. Each episode's entry SHALL carry its references and no title or
outline, until the operator titles it. A container's outline SHALL be TMDb's overview, attributed to `tmdb` with the record's id.

Each container SHALL be a draft of a new container with an id from the clone's `provisionalID()`,
kept on this Mac as a new container's draft is. The top SHALL be filed beneath the container of the
library that carries the reference of the record above it, when there is one, or at the top of the
library. The form SHALL show each episode's title from TMDb beside its entry, marked as TMDb's, and
SHALL store none. The operator SHALL be able to shape the tree before it is created: re-type a
container, group entries into child containers, and drop what they will not hold. Each entry, and each
group as one, SHALL be ticked to be made, all of them ticked to begin with; one unticked SHALL be left
out when the tree is made, a group with everything in it, and an entry naming a container the library
holds already SHALL be shown ticked and SHALL NOT be choosable. The container's heading SHALL say how
many of its entries are ticked, and tick them all or none. A tick SHALL only say whether a child is made or taken: grouping SHALL work on
the entries the operator selects, each selected alone, a range of them, or one more at a time, and
no group SHALL be selected, so that a group is made of entries alone. The grouping SHALL be offered
both above the entries and on a right-click of the selection, or of the entry clicked when it is not
selected. Once a group is made, nothing
SHALL be selected. The heading and the grouping's actions SHALL stay in sight above the entries while
the entries scroll, and choosing a new group's kind SHALL leave its title ready to be typed. Entries SHALL be
selected, and those selected made a new group, of the kind, title and label the operator gives, at the
first one's place, ticked, or added to a group the draft holds beneath the same container, the group's entries
then in the container's order. A group SHALL be ticked whole; its entries SHALL be shown in it, none
choosable, each only to be taken out of it, back beside the group; and the group SHALL be able to be
ungrouped, its entries back in its place and the specials placed in it unassigned again. A group left
with nothing SHALL be ungrouped. A run of two or more entries in one sequence whose episodes TMDb
titles as the parts of one story, as `Terror of the Zygons (1)` to `(4)` are, SHALL be bracketed and
suggested as a group titled by the story, to be grouped one at a time or all at once. No kind SHALL be
assumed for a group: the kind the container's groups mostly are SHALL be chosen to begin with, when
it has any, and otherwise the operator SHALL choose one before any group is made. A run that is the
parts of the story the container is titled as, or that is every entry the container holds, as a
group made of a story's parts holds them, SHALL NOT be suggested as a group: it SHALL be suggested
instead to be titled by its parts' numbers, as `Episode 1` and on or `Part 1` and on, as the operator
chooses, and once titled SHALL be suggested as nothing. The
console SHALL show the dry run of the whole tree as they shape it. Creating SHALL store the parent's edit
naming the top, as creating a child does, and then make the tree, with its attributions, in one
request to the silo.

#### Scenario: a film neither smddb nor the library holds
- **WHEN** the operator picks from TMDb a film whose reference neither the clone nor the library holds
- **THEN** a draft of a movie opens with the film's title and year, a `tmdb` reference and the other
  providers' ids TMDb holds, and its outline attributed to TMDb

#### Scenario: a series smddb holds
- **WHEN** the operator picks from TMDb a series whose reference a series in the clone carries
- **THEN** the console offers that series' import from smddb, and drafts nothing

#### Scenario: a season drafted beneath its series
- **WHEN** the operator picks from TMDb a season of a series the library holds by its reference, and
  creates it
- **THEN** the series' sidecar names the season, and the library holds the season with an entry for
  each episode carrying its references and no title, and no presentations

#### Scenario: a season's serials suggested from TMDb's titles
- **WHEN** a drafted season's episodes are titled at TMDb as three parts of one story, two of another,
  and one with no part number
- **THEN** the first three are suggested as a group titled by the first story, the next two as one
  titled by the second, and the last as none

#### Scenario: a serial's own parts
- **WHEN** a drafted season's three parts of one story are grouped as a serial titled by the story,
  and the serial is opened
- **THEN** its parts are not suggested as a group, and are suggested to be titled by their numbers;
  titled as parts, they are `Part 1` to `Part 3`, and are suggested as nothing

#### Scenario: a group added to and taken from
- **WHEN** an entry before a group is added to it, and its last entry is then taken out of it
- **THEN** the group holds its entries in the season's order at the first one's place, and the entry
  taken out follows the group

#### Scenario: an entry and a group unticked
- **WHEN** one of a drafted season's entries and a group of three others are unticked, and the tree is
  made
- **THEN** the season is made without the entry, and neither the group nor its three entries are made

#### Scenario: groups made one after another
- **WHEN** the operator selects three entries, makes them a group, and selects the next two
- **THEN** nothing is selected once the group is made, and only the two are selected for the next
  group; the group is never among them

#### Scenario: a group ungrouped
- **WHEN** a group a special is placed in is ungrouped
- **THEN** its entries are back in its place, and the special is unassigned again

#### Scenario: a season regrouped into serials
- **WHEN** the operator regroups a drafted season's episodes into two serials beneath it, and creates it
- **THEN** the library holds the season, with the two serials beneath it, each holding its episodes in
  TMDb's order

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aContainerIsDraftedFromTMDb`,
`aRecordSmddbHoldsIsImportedRatherThanDrafted`, `serialsAreSuggestedFromTMDbsTitlesForTheirParts`,
`aDraftsGroupIsAddedToTakenFromAndUngrouped`, `aDraftsEntryUntickedIsLeftOutOfWhatIsMade`,
`aGroupsOwnPartsAreSuggestedToBeTitledByNumberRatherThanGroupedAgain`). The search, the shaping's sheet and the dry run as the
operator shapes are pinned by nothing yet, as the rest of the shell is.

### Requirement: A series' specials are unassigned until the operator places or declines each
SiloAdmin SHALL read a series' season 0 at TMDb as the series' specials, each with its TMDb episode
id, air date, runtime, title and the provider ids TMDb holds for it, and SHALL show them beside a
draft of the series as unassigned. The operator SHALL place each special, or not, as one of these:

- an entry in one of the tree's sequences, at a position the operator chooses;
- an extra of the series or of a container beneath it, typed with one of the extra types SmdKit names;
- a child container beneath the series, drafted as a child is;
- a duplicate of another TMDb record: the special's home is the entry or container that record reads
  as, held by this library or another, or drafted or imported now, smddb first. The home's entry SHALL
  carry the special's TMDb id beside its own, and the series SHALL refer to it as `container#item`,
  from its extras or a sequence;
- an entry in a breakout, a companion series of the operator's own beside the series: any series the
  library holds other than the one being drafted or walked, listed or unlisted, or a new one with the
  title the operator gives it, unlisted to begin with and listed when the operator says, created at
  the top of the library before anything that refers to it; the series SHALL refer to the entry in
  it, from its extras or a sequence;
- an alternative of the container it is placed in, a cut naming the sequence it plays: an entry in an
  alternate sequence the container has, at a position; the only entry of a new sequence, named by a
  new alternative with the title the operator gives it, as an omnibus edition is; or an entry in a new
  sequence that holds the special in place of one item of another sequence and refers to each of that
  sequence's other items, named by a new alternative, as a version of one episode is;
- declined, which SHALL record the special's ref as declined in the series' sidecar.

For each special the console SHALL pre-fill a suggestion and the reason for it, and SHALL take none
until the operator does. It SHALL suggest, strongest first: where smddb's record of the series files
the special's ref, when the clone holds the series; the breakout that holds the specials before and
after it in TMDb's season 0 order; a duplicate of the TMDb record whose IMDb or TVDB id the special
shares, found through TMDb's lookup by external id; the position an episode group of the series gives
the special; a new edition of a container whose title the special's title names, beside a word such as
"Omnibus" or when the special runs within a tenth of one of the container's sequences together; a
version of an item whose title the special's title names beside words such as "Special Edition"; in a
walk, each of these two read from the stops read so far, in place of a weaker suggestion; an entry
between the two episodes the special aired between; and, for a short special whose title names it as
one, an extra of the type its title suggests, or declined for a trailer. A special left unassigned
SHALL NOT stop the tree from being created, and creating SHALL hold none of the unassigned. Placing a
special in a duplicate's home or a breakout that the library holds SHALL be an edit of that container,
and the console SHALL list every edit and creation the placements make before it stores any.

#### Scenario: a special that is also a TMDb movie
- **WHEN** a series' special shares its IMDb id with a TMDb movie that another library holds, and the
  operator takes the suggestion
- **THEN** the movie's entry carries the special's TMDb id beside its own, and the series refers to
  that entry

#### Scenario: specials broken out into a series of their own
- **WHEN** the operator files two of a series' specials in a new unlisted breakout, from the extras of
  two serials
- **THEN** the library holds the breakout with an entry for each special carrying its TMDb id, and
  each serial's extras refer to its entry

#### Scenario: the next special suggested for the breakout
- **WHEN** the specials just before and just after an unassigned special in TMDb's season 0 order
  were filed in a breakout
- **THEN** the unassigned special is suggested for the same breakout, with that as its reason

#### Scenario: a trailer declined
- **WHEN** the operator declines a special and creates the series
- **THEN** the series' sidecar declines the special's ref, and the library holds no entry for it

#### Scenario: specials left unassigned
- **WHEN** the operator creates a series with every special unassigned
- **THEN** the library holds the series and its seasons, and no special

#### Scenario: an omnibus edition
- **WHEN** a special is placed as a new edition of a serial, titled by the operator
- **THEN** the serial gains a sequence holding only the special's entry, carrying its references, and
  an alternative with that title naming the sequence, and its other sequences are unchanged

#### Scenario: one episode with new effects
- **WHEN** a special is placed as a version of the first of a serial's four episodes
- **THEN** the serial gains a sequence holding the special's entry first and referring to the other
  three episodes, and an alternative naming it, and the serial still holds one entry for each episode

#### Scenario: an alternative suggested
- **WHEN** a special's title names a serial beside the word "Omnibus", and another's names one of the
  serial's episodes beside the words "Special Edition"
- **THEN** the first is suggested as a new edition of the serial, and the second as a version of that
  episode, each with that as its reason

#### Scenario: a companion series the library holds
- **WHEN** a special is placed in a listed series the library already holds, referred to from a
  season's extras
- **THEN** that series' edit adds an entry carrying the special's references, the season's extras
  refer to it, and the series stays listed

#### Scenario: a new companion series made listed
- **WHEN** a special is placed in a new companion series the operator titles and lists
- **THEN** the companion series is created listed, holding the special's entry, before the edit that
  refers to it

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aSeriesSpecialsArePlacedFromThePool`,
`aSpecialIsSuggestedAsAMoviesDuplicate`, `aSpecialPlacedAsANewEditionIsASequenceOfItsOwn`,
`aSpecialPlacedAsAVersionOfAnEpisodeRefersToTheRest`,
`anOmnibusAndASpecialEditionAreSuggestedAsAlternatives`,
`aSpecialIsPlacedInACompanionSeriesTheLibraryHolds`,
`aNewCompanionSeriesIsCreatedListedWhenTheOperatorSays`). The pool and its choosing are pinned by
nothing yet, as the rest of the shell is.

### Requirement: A held container's differences from TMDb are listed, and the operator takes each or leaves it
For a container the library holds, SiloAdmin SHALL read TMDb's record of the container's `tmdb`
reference, as a draft from TMDb reads it. A container with no `tmdb` reference of its own SHALL be read
through the nearest container above it that has one, or, when none above it has one, through a
container of the library that refers to its items; its differences SHALL be about the entries it
holds. Picking from TMDb a record whose reference a container of the library carries SHALL open that
container's differences. A TMDb id SHALL count as covered when the container, a container beneath it,
or an item the container refers to carries it, or when the container's sidecar declines it. The
console SHALL list how the library's sidecar differs from the reading:

- a title, year or outline that differs, the outline shown with its attribution;
- each provider's id TMDb holds that the sidecar lacks, for the container and for each entry it holds;
- each of TMDb's episodes or seasons, other than a special, whose id is not covered, with where TMDb
  puts it;
- items that both hold, at the same level, in a different order;
- each artwork kind the container's folder has no file for and TMDb has an image for;
- for a series, each special whose id is not covered, as unassigned, to be placed or declined as a
  draft's specials are, with its suggestion;
- for a series, collapsed, each special its sidecar declines, which the operator may place after all,
  removing the decline.

An item, child or extra the library holds and TMDb does not SHALL be shown, and SHALL NOT be offered
for removal. Each difference SHALL be chosen or not, none chosen to begin with, and one not chosen
SHALL change nothing. Each group's differences SHALL be chosen all at once or none, the group showing
when only some of them are chosen. Confirming the container's stop in a walk SHALL keep its chosen
field, reference, entry and order differences as one pending edit of the container, based on the
sidecar its stop read, carrying the outline's attribution when the outline is chosen, and the declined
refs when a special is declined or placed after all, and stored when the walk is stored. A special
placed in a duplicate's home or a breakout SHALL be an edit of that container too, and the console
SHALL list every edit before it stores any. A chosen child container SHALL join the walk as a new stop
beneath the container. The episodes a held container lacks SHALL be groupable into new containers
beneath it as a draft's entries are, a group of the kind, title and label the operator gives, made
of the episodes selected, as a draft's entries are, ticked, or added to a group made there already; runs TMDb titles as the parts of one
story SHALL be suggested as a draft's are, but for a run of the story the held container is titled
as, which is its own parts. A group SHALL be chosen whole, its episodes shown in it,
each only to be taken out of it or the group ungrouped, each episode then chosen as the group was. A
group chosen SHALL be made, when the walk is stored, as a container beneath the held one holding its
episodes in TMDb's order, named in the held container's edit where the first of them would have gone,
and none of its episodes SHALL be added to the held container itself. Confirming the held
container's stop SHALL add each group it takes to the walk as a new stop beneath it, holding its
episodes, where specials SHALL be placeable and its parts shaped as in a new stop drafted from TMDb;
storing the walk SHALL make it from that stop once the stop is confirmed, with what was placed and
shaped there, and as the group otherwise. A group whose episodes change SHALL be a new stop again,
the specials placed in it unassigned, once the held container's stop is confirmed again, and one
ungrouped or unchosen SHALL leave the walk then. Each container the held one
holds beneath it SHALL be shown among its children, at the place of the first of TMDb's episodes it
holds, or after them when it holds none, and its missing episodes selected SHALL be addable to it as
to a group made there, each only to be taken out of it again, chosen then, or grouped instead. One
put there SHALL be one of that container's own missing episodes from then on, chosen at its stop to
begin with, and grouped and taken there as any of its own are; none of them SHALL be added to the held
container itself, and an entry TMDb puts after one of them SHALL follow the container.
Chosen artwork SHALL be put with its attribution when the walk is stored. The
console SHALL read a container against TMDb only when its stop is opened, or as the next stop to be
opened.

#### Scenario: an episode TMDb has gained
- **WHEN** a season the library holds lacks an episode TMDb's record of the season has, and the
  operator chooses that difference alone, confirms the season's stop and stores the walk
- **THEN** the season's edit adds one entry carrying the episode's references at TMDb's position, and
  changes nothing else

#### Scenario: missing episodes grouped
- **WHEN** a held season lacks four parts of one story and the first part of the next, the four are
  grouped as a serial, all five are chosen, and the walk is stored
- **THEN** the serial is created beneath the season holding the four, the season's edit names it where
  the first part would have gone, and the next story's part follows it

#### Scenario: a group of missing episodes as a new stop
- **WHEN** a held season's missing parts of one story are grouped as a serial and chosen, the season's
  stop is confirmed, a special is placed as an extra of the serial at its stop, that stop is confirmed,
  and the walk is stored
- **THEN** the serial is a new stop beneath the season, created holding the parts with the special as
  its extra, and the season's edit names it where the first part would have gone

#### Scenario: missing parts added to a serial held beneath
- **WHEN** a held season holds a serial beneath it holding the first story's parts, lacks two parts of
  the next story, which are added to that serial, chooses the third part, confirms the serial's
  stop with both of the two chosen there, and the walk is stored
- **THEN** the serial is shown among the season's children before the missing parts, the serial gains
  the two parts after its own, and the season's edit adds the third part after the serial and neither
  of the two

#### Scenario: an extra TMDb does not know
- **WHEN** a container the library holds has an extra that TMDb's record has nothing for
- **THEN** the extra is shown, and nothing offers to remove it

#### Scenario: a serial with no reference of its own
- **WHEN** a serial with no TMDb reference, beneath a season that has one, holds an episode whose
  IMDb id TMDb holds and the serial's sidecar lacks
- **THEN** the serial's differences list that IMDb id against the episode's entry

#### Scenario: episodes regrouped into serials
- **WHEN** a season holds every one of TMDb's episodes for it within serials beneath it
- **THEN** no episode is listed as missing, and no order difference is listed

#### Scenario: specials placed elsewhere or declined
- **WHEN** a series refers to one special's home in another library and to another special's entry in
  a breakout, and its sidecar declines a third
- **THEN** none of the three is listed as unassigned, and the third is listed among the declined

#### Scenario: a special TMDb has gained
- **WHEN** TMDb's season 0 for a series the library holds has gained a special nothing covers
- **THEN** the special is listed as unassigned, with a suggestion, and not as a missing episode

#### Scenario: a breakout read through the series that refers to it
- **WHEN** a breakout with no TMDb reference holds entries a series refers to, and TMDb holds an IMDb
  id for one of those specials that the breakout's entry lacks
- **THEN** the breakout's differences list that IMDb id against the entry

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aHeldContainersDifferencesFromTMDbAreTakenOrLeft`,
`aHeldSeasonsMissingEpisodesGroupedAreMadeAContainerBeneathIt`,
`aHeldSeasonsMissingEpisodesAreAddedToAContainerHeldBeneathIt`,
`aHeldSeasonsGroupsAreNewStopsBeneathItOnceConfirmed`). The list and its choosing are pinned by nothing
yet, as the rest of the shell is.

### Requirement: A reading against TMDb says each step as it goes, and shows what it has found
While SiloAdmin reads a held container against TMDb, the console SHALL show the step the reading is
on and, for a step that asks a question of each of several items, how many of them are answered. The
differences found so far SHALL be shown as they are found, and a series' uncovered specials SHALL be
listed as unassigned while their suggestions are read; no difference SHALL be taken until the reading
is over. A reading that fails SHALL say why, with what it found before it stopped. Closing a
container's differences SHALL stop its reading. While a draft's specials' suggestions are read, the
console SHALL show how many are read. SiloAdmin SHALL ask a step's questions of TMDb and the silo
several at once, and no more than six at once. When TMDb answers that too many are being asked, the
request SHALL be asked again after the wait TMDb names, at most three times, before the console says
what TMDb answered.

#### Scenario: a series whose specials are being suggested
- **WHEN** a held series, two of whose seasons and all of whose specials nothing covers, is read
  against TMDb
- **THEN** each step is said as it goes, each counted step counting from none to all of its items, and
  the specials are listed as unassigned while their suggestions are read

#### Scenario: a series with many specials
- **WHEN** a held series has twenty specials nothing covers
- **THEN** TMDb is asked about several of them at once, and never about more than six at once

#### Scenario: TMDb asked too much at once
- **WHEN** TMDb answers a request twice that too many are being asked, naming a wait of no time,
  and then answers it
- **THEN** the request is asked three times and its answer read; a request TMDb refuses so four times
  is said to have been answered 429

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aComparisonSaysEachStepAsItGoesWithWhatItHasFound`, `aComparisonAsksTMDbSeveralQuestionsAtOnce`);
`Tests/SiloAdminKitTests/TMDbClientTests.swift` (`tooManyAtOnceIsAskedAgainAfterTMDbsWait`). The
sheets' showing it is pinned by nothing yet, as the rest of the shell is.

### Requirement: A held container's tree is reviewed against TMDb as a walk, a container at a time
Opening a held container's differences SHALL start a walk rooted at it, whose first stop is the
container. Confirming a stop SHALL keep its chosen differences as the container's pending change, and
SHALL add as pending stops beneath it each container the library holds beneath it, in the order its
sequences hold them; confirming a stop with nothing chosen SHALL record it as looked at. Pending stops
SHALL be opened in the tree's order, depth first. The console SHALL show the walk's tree as far as the
walk has found it, each stop with its state: pending, open, changed, or looked at. The operator SHALL
be able to open any stop of the walk, and a confirmed stop SHALL open with its choices and placements
as they were left; confirming it again SHALL replace its pending change. When the walk's root is a
series, or is beneath one, the series' unassigned specials SHALL be shown beside every stop with their
suggestions. A special suggested for the open stop SHALL be marked as suggested there only on
something that ties it there: its title naming the stop, an entry of it, the story TMDb titles an
entry a part of, or a container beneath it; or smddb filing it there. A series' own title, which any
of its specials may carry, SHALL tie nothing. A special SHALL be
placeable in the open stop, as an entry in a sequence of it at a position or as one of its extras, and
anywhere a draft's specials may be placed. A placed special SHALL leave the unassigned specials and
become part of the pending change of the container it was placed in, and removing it from that change
SHALL return it. A stop never opened, and a special never placed, SHALL change nothing.

Nothing SHALL be stored until the operator stores the walk. Before storing, the console SHALL list
every creation, edit and artwork put the walk makes, in the order it will make them: the companion
series it makes at the top of the library; the edits that specials placed elsewhere make of containers
outside the walk, so that what the walk's edits refer to is there; each changed container's edit, in
the tree's order, each followed by the creation of the containers it names beneath it, since a
container is created beneath a parent only once the parent names it; and the artwork. An edit a
placement makes of a container that is a confirmed stop SHALL be part of that stop's edit. Storing
SHALL make them in that order and stop at the first refusal, saying what was stored and what was not,
and the walk SHALL keep what was not.

#### Scenario: a series confirmed with nothing chosen
- **WHEN** a held series holding three seasons, each holding serials, is confirmed with nothing chosen
- **THEN** the series is looked at, its three seasons are pending in the order its sequence holds them,
  and confirming the first season makes its serials pending ahead of the second season

#### Scenario: a special placed where it belongs
- **WHEN** one of a series' unassigned specials is placed as an entry of a season while the season's
  stop is open, and the walk is stored
- **THEN** the season's edit adds an entry carrying the special's references, and the special is no
  longer unassigned

#### Scenario: a special suggested where it aired
- **WHEN** a special is suggested for a season for when it aired alone, and another, titled as the
  making of a serial beneath the season, is suggested for the season too
- **THEN** only the second is marked as suggested there

#### Scenario: a stop opened again
- **WHEN** a confirmed season is opened again from the walk's tree, one more difference is chosen, and
  the season is confirmed again
- **THEN** its earlier choices are shown as they were left, and its pending change holds both
  differences

#### Scenario: a walk stored before its end
- **WHEN** a walk is stored with stops it never opened
- **THEN** only the confirmed stops' changes are stored

#### Scenario: a refusal part of the way through
- **WHEN** the silo refuses the second of a walk's three edits
- **THEN** the first is stored, the second and third are not, and the walk keeps the second and third

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`confirmingAStopQueuesTheContainersBeneathItInTheTreesOrder`,
`aSpecialPlacedAtAStopIsStoredInThatContainersEdit`, `aConfirmedStopOpenedAgainKeepsWhatWasChosen`,
`aWalkStoresOnlyWhatWasConfirmed`, `aWalksStoreStopsAtTheFirstRefusal`,
`anEditOfAConfirmedStopIsPartOfThatStopsEdit`, `aSpecialIsSuggestedHereOnlyWhenItsTitleTiesItThere`). The walk's sheet is pinned by nothing yet, as the rest
of the shell is.

### Requirement: A missing child chosen in a walk is a new container, created when the walk is stored
A missing child chosen at a stop of a walk SHALL join the walk, when the stop is confirmed, as a new
stop beneath it: a draft from TMDb, read as a draft from TMDb reads it, with ids from smddb's client.
It SHALL be drafted once, however many times the stop is confirmed, and the console SHALL take no
second confirm of a stop while one is under way. The walk's tree SHALL show it as new. Its fields and
references, and any artwork TMDb offers for it, SHALL be chosen to begin with. It SHALL be shaped as a
draft from TMDb is shaped, and each container the shaping makes beneath it SHALL be a new stop; one
the shaping ungroups, or unticks, SHALL leave the walk, and the specials placed in it SHALL be
unassigned again; one ticked again SHALL be a new stop once the stop above it is confirmed again.
Specials SHALL be placeable in a new stop as in a held one, and a new stop SHALL show the specials
placed in it as a held stop does, each with how it was placed and a way to unassign it. A new stop
SHALL be made only once it is confirmed: storing the walk SHALL create it through the create route,
with the containers beneath it in one creation, right after the edit of its parent that names it, since
the create route makes a container beneath a parent only once the parent names it. Unchoosing a missing
child and confirming its parent's stop again SHALL remove its new stop and every stop beneath it from
the walk, after the console says which, and the specials placed in them SHALL be unassigned again.

#### Scenario: a season TMDb has that the library lacks
- **WHEN** a missing season is chosen at a held series' stop, and the stop is confirmed
- **THEN** the season is a new stop beneath the series, titled as TMDb titles it, with TMDb's year and
  references chosen

#### Scenario: a stop confirmed twice at once
- **WHEN** a missing season is chosen at a held series' stop, and the stop is confirmed twice before
  either confirm has finished
- **THEN** the season is one new stop beneath the series

#### Scenario: a special placed in a new season
- **WHEN** a special is placed as an entry of a new season, and the walk is stored
- **THEN** the season is created holding the entry, after the series' edit that names the season

#### Scenario: a special placed as an extra of a new serial
- **WHEN** a special is placed as an extra of a serial a new season's episodes were grouped into, while
  the serial's stop is open
- **THEN** the serial's stop shows the special among those placed there, as an extra of the serial, and
  unassigning it there returns it to the unassigned specials

#### Scenario: a new season regrouped
- **WHEN** a new season's episodes are regrouped into two serials
- **THEN** each serial is a new stop beneath the season

#### Scenario: a new season's serial ungrouped
- **WHEN** a serial a new season's episodes were grouped into, with a special placed in it, is
  ungrouped
- **THEN** the serial's stop leaves the walk, and the special is unassigned again

#### Scenario: a new season's serial unticked
- **WHEN** a serial a new season's episodes were grouped into, with a special placed in it, is
  unticked, and later ticked again and the season confirmed again
- **THEN** the serial's stop leaves the walk and the special is unassigned again, and once ticked again
  the serial is a stop beneath the season once more

#### Scenario: a new season unchosen
- **WHEN** a missing season chosen earlier is unchosen, and the series' stop is confirmed again
- **THEN** the season's stop and its serials' stops leave the walk, and a special placed in one of them
  is unassigned again

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aMissingSeasonChosenInAWalkIsANewStop`,
`aStopConfirmedTwiceAtOnceDraftsItsSeasonsOnce`, `aSpecialPlacedInANewSeasonIsCreatedWithIt`,
`aNewSeasonsSerialsAreStopsBeneathIt`, `aGroupUngroupedInANewStopLeavesTheWalk`,
`aGroupLeftOutOfANewStopLeavesTheWalkUntilTickedAgain`,
`unchoosingAMissingSeasonRemovesItsStops`). The walk's sheet is
pinned by nothing yet, as the rest of the shell is.

### Requirement: A walk is kept on this Mac until it is stored or discarded
A walk SHALL be kept on this Mac, with its stops, their states, choices and placements, and the series'
unassigned specials, until it is stored whole or the operator discards it. Opening the differences of a
container that roots a kept walk SHALL offer to resume the walk or start again. The silo SHALL hold
nothing of a walk. An edit whose sidecar has changed since its stop read it SHALL be refused as a stale
edit is, the store SHALL stop there and say so, and the stop SHALL be read again and be pending, its
choices kept, until the operator confirms it again.

#### Scenario: a walk resumed
- **WHEN** a walk with two confirmed stops and one placed special is kept, and the console is opened
  again
- **THEN** resuming the walk shows the same stops, states, choices and placement

#### Scenario: a walk discarded
- **WHEN** a kept walk is discarded
- **THEN** opening its root's differences starts a new walk

#### Scenario: a sidecar changed behind the walk
- **WHEN** a stop's sidecar changes in the library after the stop was read, and the walk is stored
- **THEN** that stop's edit is refused, the store stops there and says so, and the stop is read again

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aWalkIsKeptOnThisMacAndResumed`,
`aDiscardedWalkIsGone`, `aStopWhoseSidecarChangedIsReadAgain`). The offer to resume is pinned by
nothing yet, as the rest of the shell is.

### Requirement: A held season carrying no TMDb id matches nothing until the operator says which it is
A season beneath a series that carries a `tmdb` reference, and that carries none itself, SHALL match
nothing at TMDb: its stop SHALL say so, and SHALL list the series' seasons at TMDb for the operator to
say which it is, the one suggested chosen to begin with. The season SHALL be suggested to be the one
TMDb names as its title is, else the one whose number its title gives, as `Season 13` gives 13, else
the one TMDb finds an episode beneath it in by the episode's other ids. Until the operator says which,
nothing SHALL be read against the season, and a container beneath it SHALL be read through nothing and
say why. Once the operator says which, the season, and every stop beneath it, SHALL be read again as
that season, its stop pending again, and the season's TMDb id SHALL be offered and chosen. The operator
SHALL be able to say it is unmatched again. A series' stop SHALL list, among its children, each of
TMDb's seasons the library holds beneath it, by its `tmdb` reference or as the season suggested for a
held season carrying none, saying which; such a season SHALL be a stop of the walk whatever is chosen,
SHALL NOT be choosable, and SHALL NOT be offered as missing. An item carrying no `tmdb` reference SHALL
be matched to the episode TMDb finds by its other ids, and SHALL NOT be listed as held only or its
episode as missing; one held at the stop's own level SHALL be offered TMDb's id. Once the operator says
which season a held one is, the series' stop SHALL list that season as held by it, as they said, and
a season it was only suggested to be, when they said another, SHALL be listed as missing again, without
the series being read again; a season said to be held SHALL NOT be drafted.

#### Scenario: a season imported without TMDb's id
- **WHEN** a series holds a season titled with its number and no TMDb id, holding one of TMDb's two
  serials for that season
- **THEN** the series' stop lists TMDb's season as perhaps the held one, offering it as missing nowhere,
  and the season's stop says it matches nothing at TMDb, suggesting TMDb's season of that number

#### Scenario: the operator says it is another season
- **WHEN** the operator says the season is TMDb's next season, not the one suggested
- **THEN** the series' stop lists the next season as held by it, and the one suggested as missing

#### Scenario: the operator says which season it is
- **WHEN** the operator says the season is TMDb's season of that number
- **THEN** the season's stop offers TMDb's id for it, chosen, and lists the other serial's episodes as
  missing, and the serial's stop offers TMDb's ids for the parts that carry only TheTVDB's

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aSeasonCarryingNoTMDbIdMatchesNothingUntilSaid`, `anUnmatchedSeasonIsSuggestedByItsNumberOrItsEpisodes`).
The stop's list of TMDb's seasons is pinned by nothing yet, as the rest of the shell is.
