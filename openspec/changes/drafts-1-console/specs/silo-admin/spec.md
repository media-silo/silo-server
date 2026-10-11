<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

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

Pinned by: nothing yet.

## MODIFIED Requirements

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
`Tests/SiloAdminTests/ConsoleModelTests.swift` (`aDraftIsCheckedAsItIsTypedAndOutlivesItsSection`).
A draft kept on disk, listed under its branch and marked behind is pinned by nothing yet.

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

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`forgetPurgesTheRegistryAndThePasskey`, `aRediscoveryRestartsHistory`). Forgetting a silo's drafts is pinned by nothing yet.
