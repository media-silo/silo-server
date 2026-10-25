<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A series' specials are unassigned until the operator places or declines each
SiloAdmin SHALL read a series' season 0 at TMDb as the series' specials, each with its TMDb episode
id, air date, runtime, title and the provider ids TMDb holds for it, and SHALL show them beside a
draft of the series as unassigned. The operator SHALL place each special, or not, as one of these:

- an entry in one of the tree's sequences, at a position the operator chooses;
- an extra of the series or of a container beneath it, typed with one of the extra types SmdKit names;
- a child container beneath the series, drafted as a child is;
- a duplicate of another TMDb record: the special's home is the entry or container that record reads
  as, held by this library or another, or drafted or imported now, smddb first. The home's entry SHALL
  carry the special's TMDb id beside its own, and the series SHALL refer to it as `container#item`,
  from its extras or a sequence;
- an entry in a breakout, a companion series of the operator's own beside the series: any series the
  library holds other than the one being drafted or walked, listed or unlisted, or a new one with the
  title the operator gives it, unlisted to begin with and listed when the operator says, created at
  the top of the library before anything that refers to it; the series SHALL refer to the entry in
  it, from its extras or a sequence;
- an alternative of the container it is placed in, a cut naming the sequence it plays: an entry in an
  alternate sequence the container has, at a position; the only entry of a new sequence, named by a
  new alternative with the title the operator gives it, as an omnibus edition is; or an entry in a new
  sequence that holds the special in place of one item of another sequence and refers to each of that
  sequence's other items, named by a new alternative, as a version of one episode is; or an entry
  joining an alternative the container holds or another special's placement makes, last in its
  sequence or in the place of an item the sequence refers to. Specials joining an alternative SHALL be
  placed after those that make one, whatever order TMDb lists them in, and a special that made an
  alternative SHALL, when placed so it makes none in that container, return those joining it to the
  unassigned;
- declined, which SHALL record the special's ref as declined in the series' sidecar.

For each special the console SHALL pre-fill a suggestion and the reason for it, and SHALL take none
until the operator does. It SHALL suggest, strongest first: where smddb's record of the series files
the special's ref, when the clone holds the series; the breakout that holds the specials before and
after it in TMDb's season 0 order; a duplicate of the TMDb record whose IMDb or TVDB id the special
shares, found through TMDb's lookup by external id; the position an episode group of the series gives
the special; a new edition of a container whose title the special's title names, beside a word such as
"Omnibus" or when the special runs within a tenth of one of the container's sequences together; a
version of an item whose title the special's title names beside words such as "Special Edition"; in a
walk, each of these two read from the stops read so far, in place of a weaker suggestion; an entry
between the two episodes the special aired between; and, for a short special whose title names it as
one, an extra of the type its title suggests, or declined for a trailer. A special left unassigned
SHALL NOT stop the tree from being created, and creating SHALL hold none of the unassigned. Placing a
special in a duplicate's home or a breakout that the library holds SHALL be an edit of that container,
and the console SHALL list every edit and creation the placements make before it stores any.

#### Scenario: a special that is also a TMDb movie
- **WHEN** a series' special shares its IMDb id with a TMDb movie that another library holds, and the
  operator takes the suggestion
- **THEN** the movie's entry carries the special's TMDb id beside its own, and the series refers to
  that entry

#### Scenario: specials broken out into a series of their own
- **WHEN** the operator files two of a series' specials in a new unlisted breakout, from the extras of
  two serials
- **THEN** the library holds the breakout with an entry for each special carrying its TMDb id, and
  each serial's extras refer to its entry

#### Scenario: the next special suggested for the breakout
- **WHEN** the specials just before and just after an unassigned special in TMDb's season 0 order
  were filed in a breakout
- **THEN** the unassigned special is suggested for the same breakout, with that as its reason

#### Scenario: a trailer declined
- **WHEN** the operator declines a special and creates the series
- **THEN** the series' sidecar declines the special's ref, and the library holds no entry for it

#### Scenario: specials left unassigned
- **WHEN** the operator creates a series with every special unassigned
- **THEN** the library holds the series and its seasons, and no special

#### Scenario: an omnibus edition
- **WHEN** a special is placed as a new edition of a serial, titled by the operator
- **THEN** the serial gains a sequence holding only the special's entry, carrying its references, and
  an alternative with that title naming the sequence, and its other sequences are unchanged

#### Scenario: one episode with new effects
- **WHEN** a special is placed as a version of the first of a serial's four episodes
- **THEN** the serial gains a sequence holding the special's entry first and referring to the other
  three episodes, and an alternative naming it, and the serial still holds one entry for each episode

#### Scenario: two specials in one alternative
- **WHEN** one special is placed as a version of a serial's first episode, a special TMDb lists before
  it joins that alternative in the place of the second episode, and a third joins it last
- **THEN** the serial gains one sequence, playing the three specials in those places and the serial's
  third and fourth episodes between them, named by one alternative

#### Scenario: an alternative's maker placed elsewhere
- **WHEN** a special that made an alternative another special joins is placed as an extra
- **THEN** the special that joined it is unassigned again

#### Scenario: an alternative suggested
- **WHEN** a special's title names a serial beside the word "Omnibus", and another's names one of the
  serial's episodes beside the words "Special Edition"
- **THEN** the first is suggested as a new edition of the serial, and the second as a version of that
  episode, each with that as its reason

#### Scenario: a companion series the library holds
- **WHEN** a special is placed in a listed series the library already holds, referred to from a
  season's extras
- **THEN** that series' edit adds an entry carrying the special's references, the season's extras
  refer to it, and the series stays listed

#### Scenario: a new companion series made listed
- **WHEN** a special is placed in a new companion series the operator titles and lists
- **THEN** the companion series is created listed, holding the special's entry, before the edit that
  refers to it

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aSeriesSpecialsArePlacedFromThePool`,
`aSpecialIsSuggestedAsAMoviesDuplicate`, `aSpecialPlacedAsANewEditionIsASequenceOfItsOwn`,
`aSpecialPlacedAsAVersionOfAnEpisodeRefersToTheRest`,
`anOmnibusAndASpecialEditionAreSuggestedAsAlternatives`,
`specialsJoinAnAlternativeAnotherSpecialMakes`,
`aSpecialIsPlacedInACompanionSeriesTheLibraryHolds`,
`aNewCompanionSeriesIsCreatedListedWhenTheOperatorSays`). The pool and its choosing are pinned by
nothing yet, as the rest of the shell is.
