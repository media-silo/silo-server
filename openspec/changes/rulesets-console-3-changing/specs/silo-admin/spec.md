<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

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
`aSettingsChangeSendsOnlyWhatChangedAndARenameIsRendered`), which pin the engine the pane is drawn
from; the pane itself, and naming a library's standard, are pinned by nothing yet.

## ADDED Requirements

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

Pinned by: nothing yet.

### Requirement: Nothing is stored before the draft's difference and impact are shown
Before a draft can be stored, SiloAdmin SHALL show its text's difference from its base and its impact
as the silo reports it — every placed presentation the draft would make differently, and how — and
SHALL make none of them again.

#### Scenario: a bitrate lowered
- **WHEN** a draft lowers the commentary bitrate of a ruleset whose version made 41 placed
  presentations, 12 of them with a commentary
- **THEN** before the store the console shows the one line that changed and the 12, each with its
  commentary's encode before and after

Pinned by: nothing yet.

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

Pinned by: nothing yet.

### Requirement: A branch is promoted from the console with its impact beside it
SiloAdmin SHALL offer to promote an open branch, showing beside it what promoting would put out of date
as the silo's branch impact gives it. A refusal SHALL be shown with the standard versions the branch
has not taken in and how they differ from its base, and the console SHALL let the operator store a
draft on the branch declaring, with `upToDateWith`, the standard's head it takes in.

#### Scenario: a promotion over the standard's work
- **WHEN** the operator promotes a branch the standard has gained version 9 since
- **THEN** the refusal names version 9 and shows how it differs from the branch's base, and promotion
  is offered again once a draft taking it in is stored on the branch

Pinned by: nothing yet.
