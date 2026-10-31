<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A stop's artwork is chosen from the images TMDb offers for the kind
For each artwork kind a stop of a walk offers, the console SHALL show the image storing the walk would
put, and, when TMDb offers more than one image for the kind, each of them, best first, with that image
marked. The image put SHALL be the first TMDb offers until the operator chooses another. Choosing
another image SHALL tick the kind, SHALL make the stop pending again if it changes the image, and
SHALL be kept with the walk. Storing the walk SHALL put the image chosen, with its attribution to TMDb.

#### Scenario: a second poster chosen
- **WHEN** a held film whose folder has no poster is walked, TMDb offering two posters for it, the
  second is chosen, and the film's stop is confirmed
- **THEN** storing the walk puts the second poster, and not the first

#### Scenario: an image chosen at a confirmed stop
- **WHEN** another poster is chosen at a confirmed stop
- **THEN** the stop is pending again

#### Scenario: an image chosen for a kind not ticked
- **WHEN** an image is chosen for an artwork kind whose difference is not ticked
- **THEN** the kind is ticked

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`artworkIsTakenFromTMDbWithItsAttribution`).
The sheet's showing the images is pinned by nothing yet, as the rest of the shell is.
