<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The console shows a silo's rulesets, their branches and versions, and the silo's reading of each
For a silo classified with access, SiloAdmin SHALL show each ruleset the silo holds, and for a ruleset
its branches — each with its base, its head, the standard version it is up to date with, and whether it
has been promoted — and its versions on each, with the number of placed presentations each made. For a
version it SHALL show the document as the silo stored it, comments and all, and beside it the silo's
reading: the rules grouped by scope in document order within each, each by the
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

### Requirement: A draft is edited as text and checked by the silo as it is typed
SiloAdmin SHALL edit a ruleset as its document's text, starting a draft from a version on screen — its
base — from a copy of any version, or from the starter: a condition-less copy
rule for each scope and the default output. A copy's `name` attribute SHALL be changed to the new
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
