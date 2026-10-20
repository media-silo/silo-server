<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The console reads smddb from a clone on this Mac, and never commits to it
SiloAdmin's settings SHALL name a folder on this Mac as a clone of smddb's data repository, and
the console SHALL read it through SmdKit's `LocalRepository`, reading it again when the app becomes
active and when the operator asks. The console SHALL NOT clone, pull, commit or push. With no
folder named, or one whose containers cannot be read, the console's smddb actions SHALL be
unavailable and SHALL say why. For each container a library holds, the browser SHALL say whether
the clone holds the same id and, when it does, whether the library's own fields match smddb's
record or differ from it, comparing the two documents without asking the silo.

#### Scenario: a container corrected in the library
- **WHEN** the operator has corrected a container's year in a library, and the clone holds the
  container with the old year
- **THEN** the browser says the library's container differs from smddb's record

#### Scenario: no clone named
- **WHEN** the console's settings name no clone
- **THEN** the smddb actions are unavailable, and say that no clone is named

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainersStandAgainstSmddb`). The setting and the reading again are pinned by nothing
yet, as the rest of the shell is.

### Requirement: A container is imported from smddb into a library, beneath the nearest ancestor the library holds
SiloAdmin SHALL let the operator search the clone's containers by title and by provider id, pick a
container, and choose which of its descendants to bring, all of them chosen to begin with and those
the library already holds shown and not choosable. The console SHALL take as the parent the nearest
of the container's ancestors in smddb that the library holds, or none, and SHALL ask the silo to
make every container from just below the parent down to the ones chosen, first as a dry run whose
writes and findings it shows, and then, when the operator confirms, for real. When the parent's
sidecar does not name the next container down, the console SHALL offer to bring the parent's own
fields from smddb as an edit draft, stored as any edit is. A container the library already holds
SHALL NOT be imported: the console SHALL offer smddb's record as an edit draft of the library's
container, based on the sidecar the browser read.

#### Scenario: a season whose series the library holds
- **WHEN** the operator imports a season from smddb into a library that holds its series, whose
  sidecar names the season
- **THEN** the console creates the season and its chosen serials beneath the series, and the
  browser shows them with no presentations

#### Scenario: a series sidecar older than smddb's record
- **WHEN** the operator imports a season whose series the library holds, and the library's series
  sidecar does not name the season
- **THEN** the dry run's refusal is shown, and the console offers an edit draft of the series with
  smddb's own fields

#### Scenario: a container the library holds
- **WHEN** the operator picks in smddb a container the library already holds
- **THEN** the console offers an edit draft of the library's container whose document is smddb's,
  and imports nothing

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aContainerIsImportedFromSmddbBeneathTheNearestHeldAncestor`). The search and the choosing are
pinned by nothing yet, as the rest of the shell is.

### Requirement: A container is created in the console with a provisional id
SiloAdmin SHALL create a container in the container form, over an empty container whose id is the
one the clone's `provisionalID()` answers, at the top of a library or as a child of a container
the library holds, at a sequence and position of the parent's the operator chooses. A new container
SHALL be a draft kept on this Mac, as an edit draft is, until it is created or discarded. Creating
a child SHALL first store an edit of the parent naming the new child, based on the parent's
sidecar, and then ask the silo to make the child. A refusal of either SHALL be shown in words and
SHALL keep the new container's draft.

#### Scenario: a container created at the top of a library
- **WHEN** the operator creates a film in a library, and stores it
- **THEN** the library holds the film with an id the clone has no file for, and no presentations

#### Scenario: a season created beneath a series
- **WHEN** the operator creates a season as the next entry of a series' seasons
- **THEN** the series' sidecar names the season, and the library holds the season beneath it

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aContainerIsCreatedWithAProvisionalID`).
The form and its drafts are pinned by nothing yet, as the rest of the shell is.

### Requirement: A library's container is proposed to smddb from its sidecar
SiloAdmin SHALL propose a library's container to smddb by contributing, through the clone, the
container's own fields as that library's sidecar says them, as a repository document. Before it
contributes, the console SHALL show the document's difference from the clone's record of the same
id, or say the clone has none, and SHALL offer with it, chosen, the containers it names that the
clone does not hold, as children beneath it or through a ref, from the library's sidecars; one the
library does not hold either SHALL be shown as the reason the contribution would be refused. After it contributes, the console SHALL say which files it
wrote in the clone. The library's sidecar SHALL NOT change, and the document SHALL carry none of
the library's presentations, children's paths or rules.

#### Scenario: a container created in the console proposed
- **WHEN** the operator proposes a container that was created in the console and is not in the
  clone
- **THEN** the console shows that the clone has no record of it, writes its file into the clone's
  containers, and says which file it wrote

#### Scenario: a correction proposed
- **WHEN** the operator proposes a container whose year was corrected in the library
- **THEN** the difference shown is the year, and the clone's file carries the corrected year and
  none of the library's presentations

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift`
(`aLibrarysContainerIsProposedToSmddb`). The review before contributing is pinned by nothing yet,
as the rest of the shell is.
