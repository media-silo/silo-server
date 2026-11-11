<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A stop is confirmed with everything beneath it in one action
Every stop of a walk SHALL offer *Confirm and everything beneath* in the menu of its *Confirm* button, whose
own action is *Confirm*, or *Unconfirm* once the stop is confirmed. It SHALL confirm the
stop with its ticks, then read each stop beneath it, with the progress a reading shows, and confirm each
with the ticks it holds: those the operator set, at the stop or through a group above it, and otherwise
the defaults, nothing at a held stop and everything at a new one. A missing child SHALL be drafted
beneath a stop only when it is ticked, so the stops confirmed are those its ticks reach. It SHALL place
no special. A stop it confirmed without the operator opening it SHALL be marked *confirmed from above* in
the sidebar until the operator opens it. A stop beneath that cannot be read SHALL be left pending with
its reason, and the rest confirmed. Storing the walk SHALL list everything the action took, as it lists
everything else, before storing any of it.

#### Scenario: a new season and its episodes
- **WHEN** a missing season is chosen at a held series' stop, and the season's new stop is confirmed with
  everything beneath
- **THEN** each of its episodes is confirmed and marked *confirmed from above*, and storing the walk
  makes the season, then each episode with its title, first date, cast and crew, and its outline
  attributed to the episode's TMDb id with the date it was read

#### Scenario: a held season with nothing ticked
- **WHEN** a held season with nothing ticked, at it or at any of its episodes, is confirmed with
  everything beneath
- **THEN** each of its episodes is confirmed with nothing taken, and storing the walk stores nothing for
  them

#### Scenario: an episode opened first keeps its own ticks
- **WHEN** a season's premiered field is ticked in its *Episodes* group, one episode's premiered is
  unticked at its own stop, and the season is confirmed with everything beneath
- **THEN** storing the walk sets every other episode's first date, and leaves that episode's as the
  library held it

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aNewSeasonConfirmedWithEverythingBeneath`,
`aHeldSeasonConfirmedWithNothingTickedStoresNothing`, `anEpisodesOwnTicksStandThroughTheFastPath`).
The sidebar's *confirmed from above* is pinned by nothing yet, as the rest of the shell is.
