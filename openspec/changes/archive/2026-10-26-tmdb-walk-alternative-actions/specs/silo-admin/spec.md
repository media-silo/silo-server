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
  alternate sequence the container has, at a position; or an entry in an alternative drafted for the
  container. The operator SHALL be able to draft an alternative of a container with a title, playing
  one special or nothing yet; cloned from one of the container's sequences, playing each item the
  sequence declares or refers to of the container's own, by reference; or cloned from another drafted
  alternative, playing what it plays, its specials included. The operator SHALL be able to place a
  special in a drafted alternative at a position or in place of one of its entries, move its entries,
  take entries out of it, retitle it and discard it. A special in more than one of a container's
  drafted alternatives SHALL be an entry of the first that plays it and referred to from the rest. A
  special replaced, taken out, or in a discarded alternative SHALL leave that alternative, staying placed
  while another still plays it, and a special placed elsewhere SHALL leave every one. Placing a special as a new edition of a container SHALL draft an alternative playing it alone,
  as an omnibus edition is, and placing it as a version of one item SHALL draft one cloned from the
  sequence holding the item with the special in the item's place, as a version of one episode is.
  Making or storing the container SHALL make each drafted alternative that plays anything as a new
  sequence holding its entries in order, each special as an entry carrying its references and each item
  as a reference to it, named by a new alternative with its title. A walk or draft kept with a special
  as a new edition or a version SHALL be read with that drafted as an alternative the special is placed
  in;
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

#### Scenario: an alternative drafted from a sequence
- **WHEN** a serial's sequence of four episodes is cloned as a new alternative, and one special is put
  in place of the first episode, another added last, the third episode taken out and the fourth moved
  before the second
- **THEN** storing makes one sequence, playing the first special, the fourth and second episodes by
  reference, then the second special, named by an alternative with the alternative's title

#### Scenario: a drafted alternative cloned
- **WHEN** a drafted alternative playing a special in place of a serial's first episode is cloned, and
  the clone has one of the serial's episodes taken out
- **THEN** storing makes both alternatives, the first holding the special's entry and the clone
  referring to it

#### Scenario: a version kept before alternatives were drafted
- **WHEN** a walk kept with a special as a version of a serial's first episode is read
- **THEN** the special is in a drafted alternative that plays it, then the serial's other episodes

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
`anAlternativeDraftedFromASequenceIsEditedAndStoredAsLeft`,
`aDraftedAlternativeClonedSharesItsSpecials`,
`versionsKeptBeforeAlternativesWereDraftedAreReadAsDrafts`, `aNewStopsDraftedAlternativesLeaveWithIt`,
`aSpecialIsPlacedInACompanionSeriesTheLibraryHolds`,
`aNewCompanionSeriesIsCreatedListedWhenTheOperatorSays`). The pool and its choosing are pinned by
nothing yet, as the rest of the shell is.

### Requirement: A held container's tree is reviewed against TMDb as a walk, a container at a time
Opening a held container's differences SHALL start a walk rooted at it, whose first stop is the
container. Confirming a stop SHALL be the operator saying it is as it should be, so that the walk need not come
back to it before it is stored: it SHALL keep its chosen differences as the container's pending change, and
SHALL add as pending stops beneath it each container the library holds beneath it, and each new one,
in the order its children list them, whatever their ids: a series' seasons in TMDb's order, a held
container's other children each at its place among its missing episodes, and a new container's in
its draft's order; a stop never read SHALL add them in the order its sequences hold them. A stop confirmed with nothing chosen and nothing placed in it SHALL be confirmed and unchanged. Pending stops
SHALL be opened in the tree's order, depth first. The console SHALL show the walk's tree as far as the
walk has found it, each stop with its state, which SHALL say what storing the walk would do: pending, not confirmed; or
confirmed, and then that storing creates its container, creates it only once a stop above it named
there is confirmed, edits it, or leaves it unchanged, as the store would find it. The operator SHALL
be able to open any stop of the walk, and a confirmed stop SHALL open with its choices and placements
as they were left. Any change to a confirmed stop's choices, a difference ticked or unticked, its
missing episodes grouped, ungrouped, titled or put into a container held beneath it, a special placed
in it or taken from it, an alternative drafted for it changed, or its draft shaped, SHALL make it pending again with its choices kept, and so
SHALL unconfirming it; a change to the missing episodes put into a held container SHALL make that
container's stop pending too. Confirming a stop again SHALL replace its pending change. When the walk's root is a
series, or is beneath one, the series' unassigned specials SHALL be shown beside every stop with their
suggestions. A special suggested for the open stop SHALL be marked as suggested there only on
something that ties it there: its title naming the stop, an entry of it, the story TMDb titles an
entry a part of, or a container beneath it; or smddb filing it there. A series' own title, which any
of its specials may carry, SHALL tie nothing. A special SHALL be
placeable in the open stop, as an entry in a sequence of it at a position or as one of its extras, and
anywhere a draft's specials may be placed. A special SHALL be draggable onto the open stop's alternatives: onto
their heading, to draft an alternative playing it alone; onto an entry of a drafted alternative, to
play in its place; or between two of its entries, to be added there. Each of the stop's sequences, the first from
its children's heading, and each drafted alternative SHALL offer to be cloned into a drafted
alternative, a drafted alternative's entries SHALL be reordered by
dragging them, and a special SHALL be draggable onto the stop's extras by kind. A placed special SHALL leave the unassigned specials and
become part of the pending change of the container it was placed in, and removing it from that change
SHALL return it. A stop SHALL show, pending or confirmed, the alternatives storing the walk would
leave its container with: those it holds or its draft has, then those the specials placed in it make,
each with its title and what it plays, in order, by title. What it shows SHALL be what storing creates. A stop never opened or left pending, and a special never placed, SHALL change nothing.

Nothing SHALL be stored until the operator stores the walk. Before storing, the console SHALL list
every creation, edit and artwork put the walk makes, in the order it will make them: the companion
series it makes at the top of the library; the edits that specials placed elsewhere make of containers
outside the walk, so that what the walk's edits refer to is there; each changed container's edit, in
the tree's order, each followed by the creation of the containers it names beneath it, since a
container is created beneath a parent only once the parent names it; and the artwork. An edit a
placement makes of a container that is a confirmed stop SHALL be part of that stop's edit. Storing
SHALL make them in that order and stop at the first refusal, saying what was stored and what was not,
and the walk SHALL keep what was not.

#### Scenario: a series confirmed with nothing chosen
- **WHEN** a held series holding three seasons, each holding serials, is confirmed with nothing chosen
- **THEN** the series is confirmed and unchanged, its three seasons are pending in TMDb's order, and
  confirming the first season makes its serials pending ahead of the second season

#### Scenario: a special placed where it belongs
- **WHEN** one of a series' unassigned specials is placed as an entry of a season while the season's
  stop is open, and the walk is stored
- **THEN** the season's edit adds an entry carrying the special's references, and the special is no
  longer unassigned

#### Scenario: a special suggested where it aired
- **WHEN** a special is suggested for a season for when it aired alone, and another, titled as the
  making of a serial beneath the season, is suggested for the season too
- **THEN** only the second is marked as suggested there

#### Scenario: a stop opened again
- **WHEN** a confirmed season is opened again from the walk's tree, one more difference is chosen, and
  the season is confirmed again
- **THEN** its earlier choices are shown as they were left, and its pending change holds both
  differences

#### Scenario: a walk stored before its end
- **WHEN** a walk is stored with stops it never opened
- **THEN** only the confirmed stops' changes are stored

#### Scenario: a refusal part of the way through
- **WHEN** the silo refuses the second of a walk's three edits
- **THEN** the first is stored, the second and third are not, and the walk keeps the second and third

#### Scenario: a held series' seasons in TMDb's order
- **WHEN** a held series' sequence holds its seasons out of TMDb's order, and its stop is confirmed
- **THEN** its seasons are queued beneath it in TMDb's order

#### Scenario: a confirmed stop changed
- **WHEN** a confirmed season's stop has a special placed in it
- **THEN** the stop is pending again with the special placed, and storing the walk stores nothing of
  it until it is confirmed again

#### Scenario: alternatives a placed special makes
- **WHEN** a serial's stop holding one alternative has one special placed as another version of its
  first episode and another as another version of the serial, before the stop is confirmed
- **THEN** the stop shows the alternative it holds, then one playing the first special in place of the
  first episode followed by the serial's other episodes, then one playing the second special alone,
  each marked as made by a placed special, and storing the walk makes those alternatives

#### Scenario: a ticked difference ticked again
- **WHEN** a difference a confirmed stop has ticked is ticked again
- **THEN** the stop stays confirmed

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`confirmingAStopQueuesTheContainersBeneathItInTheTreesOrder`,
`aStopsChildrenAreInTheOrderItsChildrenListThem`, `anyChangeToAConfirmedStopMakesItPendingAgain`,
`aSpecialPlacedAtAStopIsStoredInThatContainersEdit`, `aConfirmedStopOpenedAgainKeepsWhatWasChosen`,
`aWalkStoresOnlyWhatWasConfirmed`, `aWalksStoreStopsAtTheFirstRefusal`,
`anEditOfAConfirmedStopIsPartOfThatStopsEdit`, `aSpecialIsSuggestedHereOnlyWhenItsTitleTiesItThere`,
`aStopShowsTheAlternativesItsPlacedSpecialsMake`,
`aNewStopShowsTheAlternativesItsPlacedSpecialsMake`). The walk's sheet is pinned by nothing yet, as the rest
of the shell is, but for what its alternatives read from a drop: `Tests/SiloAdminTests/AlternativesEditorTests.swift`
(`aDragIsReadBackFromItsText`).
