<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The console reads TMDb with a token kept on this Mac, and credits it
SiloAdmin's settings SHALL take a TMDb read access token, kept in this Mac's keychain and never
written to a file by the app, and a language for TMDb's answers, the Mac's by default. The console
SHALL reach TMDb itself. The silo SHALL NOT be given the token, and SHALL NOT be asked to reach TMDb.
With no token, or one TMDb refuses, the console's TMDb actions SHALL be unavailable and SHALL say
why. The settings SHALL carry TMDb's logo and the notice that the product uses the TMDb API but is
not endorsed or certified by TMDb. Wherever the console shows something it read from TMDb, it SHALL
mark it as TMDb's.

#### Scenario: no token given
- **WHEN** the console's settings hold no TMDb token
- **THEN** the TMDb actions are unavailable, and say that no token is given

#### Scenario: a token TMDb refuses
- **WHEN** the console's TMDb token is one TMDb answers as unauthorized
- **THEN** the TMDb actions are unavailable, and say that TMDb refused the token

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`tmdbIsUnavailableWithoutAToken`). The
setting, the keychain and the credit are pinned by nothing yet, as the rest of the shell is.

### Requirement: A container is drafted from TMDb's record, and shaped before it is created
SiloAdmin SHALL search TMDb's movies and series by title. A `tmdb` reference SHALL be read by what
carries it: on a `movie` container a movie's id, on a `collection` a collection's, on a `series` a
series', on a `season` a season's, and on an entry an episode's. Picking a record whose reference the
clone holds on a container of the same kind SHALL offer that container's import from smddb, and
SHALL NOT draft it. Picking one whose reference a container of the library carries SHALL NOT draft
it, and the console SHALL say the library holds it. Otherwise the console SHALL read the record as
containers: a movie as a `movie`; a series as a `series` with a `season` child for each of TMDb's
seasons; a season as a `season` holding each of its episodes as an entry, in TMDb's order; a
collection as a `collection` with each of its movies as a child; and, when the operator chooses one
of a series' episode groups as its shape, each group as a child container of the type the operator
picks, holding the group's episodes as entries in the group's order. Each container SHALL carry the
record's title, its year where its type has one, a `tmdb` reference, and a reference for each other
provider's id TMDb holds for it. Each episode's entry SHALL carry its references and no title or
outline. A container's outline SHALL be TMDb's overview, attributed to `tmdb` with the record's id.

Each container SHALL be a draft of a new container with an id from the clone's `provisionalID()`,
kept on this Mac as a new container's draft is. The top SHALL be filed beneath the container of the
library that carries the reference of the record above it, when there is one, or at the top of the
library. The form SHALL show each episode's title from TMDb beside its entry, marked as TMDb's, and
SHALL store none. The operator SHALL be able to shape the tree before it is created: re-type a
container, regroup entries into child containers, and drop what they will not hold. The console
SHALL show the dry run of the whole tree as they shape it. Creating SHALL store the parent's edit
naming the top, as creating a child does, and then make the tree, with its attributions, in one
request to the silo.

#### Scenario: a film neither smddb nor the library holds
- **WHEN** the operator picks from TMDb a film whose reference neither the clone nor the library holds
- **THEN** a draft of a movie opens with the film's title and year, a `tmdb` reference and the other
  providers' ids TMDb holds, and its outline attributed to TMDb

#### Scenario: a series smddb holds
- **WHEN** the operator picks from TMDb a series whose reference a series in the clone carries
- **THEN** the console offers that series' import from smddb, and drafts nothing

#### Scenario: a season drafted beneath its series
- **WHEN** the operator picks from TMDb a season of a series the library holds by its reference, and
  creates it
- **THEN** the series' sidecar names the season, and the library holds the season with an entry for
  each episode carrying its references and no title, and no presentations

#### Scenario: a season regrouped into serials
- **WHEN** the operator regroups a drafted season's episodes into two serials beneath it, and creates it
- **THEN** the library holds the season, with the two serials beneath it, each holding its episodes in
  TMDb's order

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aContainerIsDraftedFromTMDb`,
`aRecordSmddbHoldsIsImportedRatherThanDrafted`). The search, the shaping and the dry run as the
operator shapes are pinned by nothing yet, as the rest of the shell is.

## MODIFIED Requirements

### Requirement: A container's own fields are edited in a form, as a draft kept on this Mac
SiloAdmin SHALL edit a container's own fields in a form: its title, year, type, type label, outline,
whether it is listed, and its external references; and its alternatives, features, sequences, items
and extras, each added, edited, removed and reordered. An outline attributed to a provider SHALL be
shown with its attribution: editing the text SHALL keep the attribution, removing the outline SHALL
remove it, and the operator MAY remove the attribution alone, which the console SHALL confirm with
them first. A draft SHALL keep its attributions of the container's own fields, and its store SHALL
carry them. An edit SHALL be a draft, kept on this Mac for the silo by its `ServerID`, the library
and the container, with the digest of the sidecar it was based on, saved a moment after the operator
stops editing so that it outlives the section, its refresh and the app. A draft whose library's
sidecar has changed since SHALL be marked behind. As the operator types, and a moment after they
stop, the console SHALL ask the silo for a dry run of the draft and show its findings. Before a
draft is stored, the console SHALL show its document's difference from the sidecar it was based on,
and the findings. A store SHALL name its base; a 409 SHALL keep the draft, show the sidecar that
landed and how it differs from the base, and offer to re-base the draft on it or discard it, and the
console SHALL NOT merge; a 422 SHALL keep the draft and show the findings that refused it. A draft
SHALL end only when it is stored or discarded, or its silo forgotten.

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

#### Scenario: an attributed outline reworded
- **WHEN** the operator rewords an outline the library's sidecar attributes to TMDb, and stores the
  draft
- **THEN** the sidecar holds the reworded outline, still attributed to TMDb

#### Scenario: an attribution removed alone
- **WHEN** the operator removes an outline's attribution, confirms it, and stores the draft
- **THEN** the sidecar holds the outline as it was, with no attribution

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainersAreBrowsedAndEditedFromTheConsole`,
`anAttributedOutlineIsKeptThroughAnEdit`). The form, the saving a moment after the
operator stops, the dry run as they type and the review are pinned by nothing yet, as the rest of
the shell is.

### Requirement: A library's container is proposed to smddb from its sidecar
SiloAdmin SHALL propose a library's container to smddb by contributing, through the clone, the
container's own fields as that library's sidecar says them, as a repository document. In each
container it contributes, a field the library's sidecar attributes to a provider SHALL take instead
the value the clone's record of the same id holds, or none when the clone has no record, and the
console SHALL list each field it left out with its provider. Before it contributes, the console
SHALL show the document's difference, as it will be contributed, from the clone's record of the same
id, or say the clone has none, and SHALL offer with it, chosen, the containers it names that the
clone does not hold, as children beneath it or through a ref, from the library's sidecars; one the
library does not hold either SHALL be shown as the reason the contribution would be refused. After
it contributes, the console SHALL say which files it wrote in the clone. The library's sidecar SHALL
NOT change, and the document SHALL carry none of the library's presentations, children's paths or
rules.

#### Scenario: a container created in the console proposed
- **WHEN** the operator proposes a container that was created in the console and is not in the
  clone
- **THEN** the console shows that the clone has no record of it, writes its file into the clone's
  containers, and says which file it wrote

#### Scenario: a correction proposed
- **WHEN** the operator proposes a container whose year was corrected in the library
- **THEN** the difference shown is the year, and the clone's file carries the corrected year and
  none of the library's presentations

#### Scenario: an attributed outline proposed
- **WHEN** the operator proposes a container whose outline the library attributes to TMDb, and the
  clone has no record of it
- **THEN** the review lists the outline as left out, attributed to TMDb, and the file written into
  the clone carries no outline

#### Scenario: an attributed outline over smddb's own
- **WHEN** the operator proposes a container whose outline the library attributes to TMDb, and the
  clone's record of it has an outline of its own
- **THEN** the difference shown has no change to the outline, and the clone's file keeps its own
  outline

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainerIsProposedToSmddb`,
`anAttributedFieldIsLeftOutOfAContribution`). The review before contributing is pinned by nothing yet,
as the rest of the shell is.
