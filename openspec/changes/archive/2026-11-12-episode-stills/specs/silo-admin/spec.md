<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A stop's artwork is chosen from the images TMDb offers for the kind
For each artwork kind a stop of a walk offers, the console SHALL show the image storing the walk would
put, and, when TMDb offers more than one image for the kind, each of them, best first, with that image
marked. The image put SHALL be the first TMDb offers until the operator chooses another. Choosing
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

### Requirement: A new stop's artwork is read with its draft and put once it is made
A draft from Wikidata SHALL read, with each container whose item Wikidata holds a TMDb id for, a film,
a series, a collection or a season, the images TMDb holds for that record, a season's through its
series, and, with each episode Wikidata holds a TMDb id for, TMDb's stills of the episode, the one its
season gives it first, offered for its `thumb` and credited to the episode's TMDb id; a draft SHALL be read without them when there is no TMDb token or TMDb does not answer. A new stop SHALL offer each artwork kind TMDb has
an image for, ticked to begin with unless this Mac's settings leave the kind unticked, and its image SHALL be chosen as a held stop's is. Storing the walk
SHALL put a new stop's ticked artwork after the containers are made, credited to the record it was read
from.

#### Scenario: a missing season's second poster
- **WHEN** a missing season is chosen at a held series' stop, TMDb offering two posters for the season,
  and at the season's new stop the second poster is chosen and the stop confirmed
- **THEN** storing the walk makes the season and then puts the second poster on it, credited to the
  season's TMDb id

#### Scenario: a drafted episode's still
- **WHEN** a season is drafted, TMDb holding stills of one of its episodes and none of another, and the
  walk is confirmed and stored
- **THEN** the first episode's new stop offers the stills for its thumb, ticked to begin with, and
  storing puts the first on the episode, credited to the episode's TMDb id; the other is offered no
  thumb

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aNewStopsArtworkIsOfferedAndPutOnceItIsMade`,
`anEpisodesStillsAreOfferedAsItsThumb`).
The new stop's pane showing it is pinned by nothing yet, as the rest of the shell is.
