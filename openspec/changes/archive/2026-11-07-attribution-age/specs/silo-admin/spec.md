<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A library's container is proposed to smddb from its sidecar
SiloAdmin SHALL propose a library's container to smddb by contributing, through the clone, the
container's own fields as that library's sidecar says them, as a repository document. In each
container it contributes, a field the library's sidecar attributes to a provider whose content is not CC0 SHALL take
instead the value the clone's record of the same id holds, or none when the clone has no record, and
the console SHALL list each field it left out with its provider. A field attributed to a provider whose
content is CC0, as Wikidata's is, SHALL be contributed as it stands, and is not left out. Before it contributes, the console
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

#### Scenario: an outline attributed to Wikidata proposed
- **WHEN** the operator proposes a container whose outline the library attributes to Wikidata, and
  one of whose alternatives' outlines it attributes to TMDb
- **THEN** the contribution carries the container's outline as it stands and no outline for the
  alternative, and lists only the alternative's outline as left out

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainerIsProposedToSmddb`,
`anAttributedFieldIsLeftOutOfAContribution`, `aFieldAttributedToACC0ProviderIsContributed`). The review before contributing is pinned by nothing yet,
as the rest of the shell is.

## ADDED Requirements

### Requirement: An attribution the console makes says the day its content was read
Each attribution SiloAdmin makes SHALL carry, as its `read`, the day the console read the content it
attributes from the provider: an outline taken into a draft from a provider's record, in a drafted
tree or at a walk's stop, and an image taken from a provider and put as a kind of a container's
artwork, each read on the day it is taken.

#### Scenario: a drafted outline
- **WHEN** a collection is drafted from TMDb's record, with TMDb's overview as its outline
- **THEN** the draft attributes the outline to TMDb's collection, read today

#### Scenario: an outline taken at a stop
- **WHEN** the operator takes TMDb's outline at a held film's stop and the walk is stored
- **THEN** the film's draft attributes the outline to TMDb's record, read today

#### Scenario: a poster taken from TMDb
- **WHEN** the operator takes one of TMDb's posters for a container
- **THEN** the image is put attributed to TMDb, read today

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aCollectionIsDraftedAndAFilmFiledBeneathTheOneHeld`,
`aFilmsAndACollectionsFieldsAreTakenFromTMDb`, `artworkIsTakenFromTMDbWithItsAttribution`).
