<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A record the library does not hold is walked from a draft of it
Picking a TMDb record that neither smddb's clone nor the library holds SHALL start a walk rooted at
the draft's top, shown in the same sheet as a walk of a held tree: the walk's tree, the open stop and,
for a series, its specials beside every stop. The root SHALL be a new stop with no stop above it in
the walk, opened, shaped and confirmed as any new stop is, its fields and references chosen to begin
with; confirming it SHALL add the containers of its draft beneath it as new stops. A drafted series
SHALL be the series whose specials sit beside every stop, each suggested where it goes as a draft's
specials are, and placed where the draft placed them; a new breakout the draft made for them SHALL be
a companion series of the walk, and the alternatives drafted for the draft's containers SHALL be the
walk's. Storing the walk SHALL make nothing of a root not confirmed. A confirmed root SHALL be
made, with the confirmed containers beneath it and their attributions, in one creation: at the top of
the library, after the walk's companion series and before any other step; or, for a film filed beneath
a collection the library holds, beneath that collection, once that collection's sidecar is edited to
name it. A drafted series SHALL then decline the specials declined in it. A creation the silo refuses
SHALL stop the store there, say why in the silo's words, and keep what was not made, to be stored
again. The walk SHALL be kept on
this Mac as a walk of a held tree is, and picking the same record for the same library again SHALL
offer to resume it or start again, starting again drafting the record afresh.

#### Scenario: a series the library lacks
- **WHEN** the operator picks a series neither the clone nor the library holds, declines its one
  special, and confirms the series' stop and the stop of its one season
- **THEN** storing the walk makes the series at the top of the library with the season beneath it,
  and the series declines the special

#### Scenario: a drafted root not confirmed
- **WHEN** a walk rooted at a draft of a series is stored before the series' stop is confirmed
- **THEN** storing makes nothing

#### Scenario: a film in a collection the library holds
- **WHEN** the operator picks a film the library lacks whose collection the library holds, and
  confirms the film's stop
- **THEN** storing the walk names the film in the collection first, then makes it beneath the
  collection

#### Scenario: a walk of a record resumed
- **WHEN** a walk rooted at a draft of a record is kept, and the same record is picked for the same
  library again
- **THEN** the console offers to resume that walk, or start again with a new draft of the record

#### Scenario: a drafted root the silo refuses
- **WHEN** a walk rooted at a draft of a film the silo's validator refuses is confirmed and stored
- **THEN** the store makes nothing, says the validator's refusal, and the film's creation is still to
  be stored

#### Scenario: a draft's new breakout
- **WHEN** a series is drafted with two of its specials placed in a new breakout, and the walk rooted
  at the draft is confirmed throughout and stored
- **THEN** the breakout is a companion series of the walk, made at the top of the library before the
  series, holding an entry for each special

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aRecordTheLibraryLacksIsWalkedFromADraft`,
`aWalkFromADraftStartsAndSuggestsAsADraftDoes`, `aDraftTheSiloRefusesIsKeptInItsWalk`,
`aSeriesSpecialsArePlacedFromThePool`). The walk's sheet, the offer to resume, and starting again are pinned by nothing yet, as the rest of
the shell is.
