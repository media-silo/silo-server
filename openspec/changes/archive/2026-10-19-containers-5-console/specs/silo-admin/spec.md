<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

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
SiloAdmin SHALL edit a container's own fields in a form: its title, year, type, type label,
outline, whether it is listed, and its external references; and its alternatives, features,
sequences, items and extras, each added, edited, removed and reordered. An edit SHALL be a
draft, kept on this Mac for the silo by its `ServerID`, the library and the container, with
the digest of the sidecar it was based on, saved a moment after the operator stops editing so
that it outlives the section, its refresh and the app. A draft whose library's sidecar has
changed since SHALL be marked behind. As the operator types, and a moment after they stop, the
console SHALL ask the silo for a dry run of the draft and show its findings. Before a draft is
stored, the console SHALL show its document's difference from the sidecar it was based on, and
the findings. A store SHALL name its base; a 409 SHALL keep the draft, show the sidecar that
landed and how it differs from the base, and offer to re-base the draft on it or discard it,
and the console SHALL NOT merge; a 422 SHALL keep the draft and show the findings that refused
it. A draft SHALL end only when it is stored or discarded, or its silo forgotten.

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

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainersAreBrowsedAndEditedFromTheConsole`). The form, the saving a moment after the
operator stops, the dry run as they type and the review are pinned by nothing yet, as the rest of
the shell is.

### Requirement: A container's artwork is shown, put and removed from the console
SiloAdmin SHALL show, for a container, each artwork kind its folder holds, and SHALL let the
operator put an image as a kind — dropped onto it, or chosen — and remove a kind, through the
library's artwork routes. A refusal SHALL be shown in words.

#### Scenario: a poster dropped
- **WHEN** the operator drops a JPEG onto a container's poster
- **THEN** the image is put, and the container shows the poster the silo serves

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainersAreBrowsedAndEditedFromTheConsole`). Dropping and choosing an image are
pinned by nothing yet, as the rest of the shell is.
