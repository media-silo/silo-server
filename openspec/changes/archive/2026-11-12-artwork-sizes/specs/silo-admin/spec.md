<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A stop's artwork is chosen from the images TMDb offers for the kind
For each artwork kind a stop of a walk offers, the console SHALL show the image storing the walk would
put, with its size in pixels when TMDb says it, and, when TMDb offers more than one image for the kind,
each of them, best first, with that image marked. The image put SHALL be the first TMDb offers until the operator chooses another. Choosing
another image SHALL tick the kind, SHALL make the stop pending again if it changes the image, and
SHALL be kept with the walk. Storing the walk SHALL put the image chosen, with its attribution to TMDb.
A held season's images SHALL be read through the series above it, which TMDb holds them beneath, and
its artwork SHALL be credited to the season's own TMDb id. A held episode whose folder has no `thumb`
SHALL be offered, for its `thumb`, TMDb's stills of it, the one its season gives it first, read beneath
the season and the series above it, and credited to the episode's own TMDb id. An image TMDb holds as an SVG SHALL be
shown, and put, as the PNG TMDb renders of it, since the silo takes artwork as a JPEG or a PNG; an
image TMDb does not give SHALL be shown as missing, not as loading.

#### Scenario: a second poster chosen
- **WHEN** a held film whose folder has no poster is walked, TMDb offering two posters for it, the
  second is chosen, and the film's stop is confirmed
- **THEN** storing the walk puts the second poster, and not the first

#### Scenario: a held season's poster
- **WHEN** a held season whose folder has no poster is walked, TMDb offering two posters for the
  season, and the second is chosen and the season's stop confirmed
- **THEN** storing the walk puts the second poster on the season, credited to the season's TMDb id

#### Scenario: a held episode's still
- **WHEN** a held episode whose folder has no thumb is walked, TMDb holding two stills of it, its
  season giving it the second
- **THEN** the episode's stop offers both for its thumb, the season's first, credited to the episode's
  TMDb id

#### Scenario: a held episode with a thumb
- **WHEN** a held episode whose folder has a thumb is walked
- **THEN** the episode's stop offers no thumb

#### Scenario: an image's size
- **WHEN** a held season is walked, TMDb offering a poster it says is 1000 by 1500 pixels and another
  whose size it does not say
- **THEN** the stop has the first poster's size as 1000 by 1500 pixels, and the other's as unknown

#### Scenario: an image chosen at a confirmed stop
- **WHEN** another poster is chosen at a confirmed stop
- **THEN** the stop is pending again

#### Scenario: an image chosen for a kind not ticked
- **WHEN** an image is chosen for an artwork kind whose difference is not ticked
- **THEN** the kind is ticked

#### Scenario: a logo TMDb holds as an SVG
- **WHEN** a logo TMDb holds as an SVG is fetched to be put
- **THEN** the console fetches the PNG TMDb renders of it, at the same path ending `.png`

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`artworkIsTakenFromTMDbWithItsAttribution`,
`aHeldSeasonsArtworkIsOfferedFromTMDbsImagesOfTheSeason`, `anEpisodesStillsAreOfferedAsItsThumb`);
`Tests/SiloAdminKitTests/TMDbClientTests.swift` (`aRecordsImagesAreListedInTheLanguageOrNoneAndFetchedWhole`,
`aSeriesIsReadWithItsSeasonsAndASeasonByItsNumber`).
The sheet's showing the images is pinned by nothing yet, as the rest of the shell is.
