<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: An item's details are a file beside its presentations, named by its item
A leaf item MAY have a details file holding its title, outline, first air date, cast, crew and the
attributions of any of them, as SmdKit's `ItemDetails` reads it. The file SHALL sit beside the item's
presentations, named `{item}.smd` with `{item}` as a presentation's file has it, or
`extras/{item}.smd` for an item the container lists as an extra, or `container - details.smd` when the
name would otherwise be `container.smd`. The item's `<item>` in its container's sidecar SHALL name the
file, relative to the folder holding the sidecar, in its `smd` attribute. Details SHALL be a library
fact, as a presentation is: the container read from a sidecar naming them SHALL be the container read
from the same sidecar without the name, and a placement SHALL keep them. The walk SHALL read each
details file an item names, and SHALL flag as an error a path that is not inside the container's folder,
a file that does not exist (`item <id>: details "<path>" do not exist`), a file whose container or
item is not the one naming it (`item <id>: details "<path>" describe <container>#<item>`), and a file
that cannot be parsed. A details file named as the layout would not name it SHALL be a warning
(`item <id>: details "<path>" are not where the layout would put them, "<expected>"`), and so SHALL an
`.smd` file other than `container.smd` that no item names (`details nothing references`). An edit that
no longer declares an item whose details the library holds SHALL be an error
(`item <id> has details in this library`).

#### Scenario: an episode's details kept through a placement
- **WHEN** an episode of a season has details, and a presentation of the episode is then placed
- **THEN** the season's sidecar still names the episode's details file, and the file is as it was

#### Scenario: details describing another item
- **WHEN** an item's `smd` names a details file whose root names a different item of the same container
- **THEN** the walk reports an error naming the item, the file and the item the file describes

#### Scenario: details nothing names
- **WHEN** a container's folder holds a details file that no item of its sidecar names
- **THEN** the walk warns `details nothing references` on that file

#### Scenario: an episode with details dropped by an edit
- **WHEN** an edit's document no longer declares an episode whose details the library holds
- **THEN** the edit is refused with the error `item <id> has details in this library`, naming the
  episode's id

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`itemDetailsAreLibraryFacts`,
`theWalkReportsBrokenOrAbandonedDetails`), `Tests/SiloTests/ServerTests.swift`
(`anEditDroppingAnItemWithDetailsIsRefused`).
