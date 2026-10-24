<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A reading against TMDb says each step as it goes, and shows what it has found
While SiloAdmin reads a held container against TMDb, the console SHALL show the step the reading is
on and, for a step that asks a question of each of several items, how many of them are answered. The
differences found so far SHALL be shown as they are found, and a series' uncovered specials SHALL be
listed as unassigned while their suggestions are read; no difference SHALL be taken until the reading
is over. A reading that fails SHALL say why, with what it found before it stopped. Closing a
container's differences SHALL stop its reading. While a draft's specials' suggestions are read, the
console SHALL show how many are read. SiloAdmin SHALL ask a step's questions of TMDb and the silo
several at once, and no more than six at once. When TMDb answers that too many are being asked, the
request SHALL be asked again after the wait TMDb names, at most three times, before the console says
what TMDb answered.

#### Scenario: a series whose specials are being suggested
- **WHEN** a held series, two of whose seasons and all of whose specials nothing covers, is read
  against TMDb
- **THEN** each step is said as it goes, each counted step counting from none to all of its items, and
  the specials are listed as unassigned while their suggestions are read

#### Scenario: a series with many specials
- **WHEN** a held series has twenty specials nothing covers
- **THEN** TMDb is asked about several of them at once, and never about more than six at once

#### Scenario: TMDb asked too much at once
- **WHEN** TMDb answers a request twice that too many are being asked, naming a wait of no time,
  and then answers it
- **THEN** the request is asked three times and its answer read; a request TMDb refuses so four times
  is said to have been answered 429

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aComparisonSaysEachStepAsItGoesWithWhatItHasFound`, `aComparisonAsksTMDbSeveralQuestionsAtOnce`);
`Tests/SiloAdminKitTests/TMDbClientTests.swift` (`tooManyAtOnceIsAskedAgainAfterTMDbsWait`). The
sheets' showing it is pinned by nothing yet, as the rest of the shell is.

## MODIFIED Requirements

### Requirement: A held container's differences from TMDb are listed, and the operator takes each or leaves it
For a container the library holds, SiloAdmin SHALL read TMDb's record of the container's `tmdb`
reference, as a draft from TMDb reads it. A container with no `tmdb` reference of its own SHALL be read
through the nearest container above it that has one, or, when none above it has one, through a
container of the library that refers to its items; its differences SHALL be about the entries it
holds. Picking from TMDb a record whose reference a container of the library carries SHALL open that
container's differences. A TMDb id SHALL count as covered when the container, a container beneath it,
or an item the container refers to carries it, or when the container's sidecar declines it. The
console SHALL list how the library's sidecar differs from the reading:

- a title, year or outline that differs, the outline shown with its attribution;
- each provider's id TMDb holds that the sidecar lacks, for the container and for each entry it holds;
- each of TMDb's episodes or seasons, other than a special, whose id is not covered, with where TMDb
  puts it;
- items that both hold, at the same level, in a different order;
- each artwork kind the container's folder has no file for and TMDb has an image for;
- for a series, each special whose id is not covered, as unassigned, to be placed or declined as a
  draft's specials are, with its suggestion;
- for a series, collapsed, each special its sidecar declines, which the operator may place after all,
  removing the decline.

An item, child or extra the library holds and TMDb does not SHALL be shown, and SHALL NOT be offered
for removal. Each difference SHALL be chosen or not, none chosen to begin with, and one not chosen
SHALL change nothing. Each group's differences SHALL be chosen all at once or none, the group showing
when only some of them are chosen. Taking the chosen field, reference, entry and order differences
SHALL make one edit draft of the container, based on the sidecar the browser read, carrying the
outline's attribution when the outline is taken, and the declined refs when a special is declined or
placed after all, and stored as any edit is. A special placed in a duplicate's home or a breakout SHALL
be an edit of that container too, and the console SHALL list every edit before it stores any. A chosen
child container SHALL open as a draft from TMDb beneath the container. Chosen artwork SHALL be put with
its attribution. The console SHALL read a container against TMDb only when the operator opens its
differences.

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

#### Scenario: specials placed elsewhere or declined
- **WHEN** a series refers to one special's home in another library and to another special's entry in
  a breakout, and its sidecar declines a third
- **THEN** none of the three is listed as unassigned, and the third is listed among the declined

#### Scenario: a special TMDb has gained
- **WHEN** TMDb's season 0 for a series the library holds has gained a special nothing covers
- **THEN** the special is listed as unassigned, with a suggestion, and not as a missing episode

#### Scenario: a breakout read through the series that refers to it
- **WHEN** a breakout with no TMDb reference holds entries a series refers to, and TMDb holds an IMDb
  id for one of those specials that the breakout's entry lacks
- **THEN** the breakout's differences list that IMDb id against the entry

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aHeldContainersDifferencesFromTMDbAreTakenOrLeft`). The list and its choosing are pinned by nothing
yet, as the rest of the shell is.
