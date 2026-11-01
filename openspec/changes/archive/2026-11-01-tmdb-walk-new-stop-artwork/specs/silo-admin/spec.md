<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A new stop's artwork is read with its draft and put once it is made
A draft from TMDb SHALL read, with each container it reads from a record of its own, a film, a series, a
collection or a season, the images TMDb holds for that record, a season's through its series; a draft
SHALL be read without them when TMDb does not answer. A new stop SHALL offer each artwork kind TMDb has
an image for, ticked to begin with, and its image SHALL be chosen as a held stop's is. Storing the walk
SHALL put a new stop's ticked artwork after the containers are made, credited to the record it was read
from.

#### Scenario: a missing season's second poster
- **WHEN** a missing season is chosen at a held series' stop, TMDb offering two posters for the season,
  and at the season's new stop the second poster is chosen and the stop confirmed
- **THEN** storing the walk makes the season and then puts the second poster on it, credited to the
  season's TMDb id

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aNewStopsArtworkIsOfferedAndPutOnceItIsMade`).
The new stop's pane showing it is pinned by nothing yet, as the rest of the shell is.
