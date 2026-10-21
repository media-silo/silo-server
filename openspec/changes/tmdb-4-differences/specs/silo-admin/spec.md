<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A held container's differences from TMDb are listed, and the operator takes each or leaves it
For a container the library holds, SiloAdmin SHALL read TMDb's record of the container's `tmdb`
reference, or, for a container with none, of the nearest container above it that has one, as a draft
from TMDb reads it. Picking from TMDb a record whose reference a container of the library carries
SHALL open that container's differences. The console SHALL list how the library's sidecar differs
from the reading:

- a title, year or outline that differs, the outline shown with its attribution;
- each provider's id TMDb holds that the sidecar lacks, for the container and for each entry it holds;
- each of TMDb's episodes or seasons whose reference nothing beneath the container carries, with
  where TMDb puts it;
- items that both hold, at the same level, in a different order;
- each artwork kind the container's folder has no file for and TMDb has an image for.

An item, child or extra the library holds and TMDb does not SHALL be shown, and SHALL NOT be offered
for removal. Each difference SHALL be chosen or not, none chosen to begin with, and one not chosen
SHALL change nothing. Taking the chosen field, reference, entry and order differences SHALL make one
edit draft of the container, based on the sidecar the browser read, carrying the outline's
attribution when the outline is taken, and stored as any edit is. A chosen child container SHALL open
as a draft from TMDb beneath the container. Chosen artwork SHALL be put with its attribution. The
console SHALL read a container against TMDb only when the operator opens its differences.

#### Scenario: an episode TMDb has gained
- **WHEN** a season the library holds lacks an episode TMDb's record of the season has, and the
  operator takes that difference alone
- **THEN** the edit draft adds one entry carrying the episode's references at TMDb's position, and
  changes nothing else

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

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aHeldContainersDifferencesFromTMDbAreTakenOrLeft`). The list and its choosing are pinned by nothing
yet, as the rest of the shell is.

## MODIFIED Requirements

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
