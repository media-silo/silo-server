<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A container that owns files is a folder named from its display title
Every container that owns files SHALL live in a folder inside its parent's folder, and a library's
roots SHALL be its top-level folders. A root's folder SHALL be named for its display title. A
container held as a child SHALL be named for its position among its parent's distinct children,
counted from one in the order the parent's `childContainerIDs` give them, written in decimal and
padded with zeros to two digits or to as many as the parent's count of children needs, followed by
` - ` and its display title (for example `13 - Season 13`). Every such folder SHALL hold one file
named `container.smd`, and a parent's sidecar SHALL record each child as the child's folder followed
by `/container.smd` (for example `13 - Season 13/container.smd`) on the child's
`<item type="container">`. A title becomes a folder or file name sanitised: `/` and `:` replaced by
`-`, NUL dropped, runs of whitespace collapsed to one space, leading dots removed and the result
trimmed. A display title that sanitises to nothing SHALL fall back to the container id's raw value.

#### Scenario: titles are sanitised for the filesystem
- **WHEN** display titles are `Doctor Who: The Movie`, `  Face/Off  `, `..hidden` and a title with runs of spaces and tabs
- **THEN** the names are `Doctor Who- The Movie`, `Face-Off`, `hidden` and the whitespace collapsed to single spaces

#### Scenario: slashes become dashes
- **WHEN** a container's title is `///`
- **THEN** its folder name is `---` — each solidus replaced — not the container id

#### Scenario: a season's serials in their order
- **WHEN** a season whose stories sequence names Terror of the Zygons, Planet of Evil and Pyramids of Mars in that order has each placed into a library
- **THEN** their folders inside the season's are `01 - Terror of the Zygons`, `02 - Planet of Evil` and `03 - Pyramids of Mars`

#### Scenario: a parent with a hundred children
- **WHEN** a series holding 120 episodes as children has its first and last placed
- **THEN** their folders begin `001 - ` and `120 - `

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`namesAreSanitised`,
`pathsAreCheckedForStayingInside`, `childFoldersAreNumberedInTheirOrder`). The fall-back to the
container id after sanitising to nothing is pinned by nothing yet.

### Requirement: The walk finds sidecars from the roots down and reports what nothing references
Walking a library SHALL find its containers from the roots: the roots are the top-level folders
that hold a `container.smd`, hidden entries skipped and folders sorted by name, and each sidecar's
`smd` paths lead to its children, read relative to the folder holding the sidecar, parents before
children. Every node SHALL record the parsed sidecar, its folder, its folder relative to the
library root, and the sidecar file's modification time and size — what an index remembers to know
whether to read it again. The walk SHALL flag as an error a child whose path is not a sidecar
inside the parent's folder, a child sidecar that does not exist
(`child <id> is at "<path>", which does not exist`), a child whose id is not the one the parent's
item names (`describes <id> where its parent expects <id>`), and a sidecar that cannot be parsed
(`unreadable: …`). Every `container.smd` under the library root that no root reached SHALL be a
warning, `a sidecar nothing references` — reachability is what keeps an abandoned draft from
changing what a client renders. Findings SHALL be sorted so a report reads the same on every
platform, and nothing the walk finds SHALL be resolved by the walk.

#### Scenario: a placed library walks to one tree
- **WHEN** `Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars` was placed with one presentation
- **THEN** the walk yields one root, finds the serial at the relative folder `Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars`, and reports no findings

#### Scenario: a child sidecar that does not exist is an error
- **WHEN** `Doctor Who (1963)/01 - Season 13/container.smd` was deleted
- **THEN** the walk reports `error: Doctor Who (1963)/container.smd: child 0000000000000002 is at "01 - Season 13/container.smd", which does not exist`

#### Scenario: sidecars nothing references are warnings
- **WHEN** the season's sidecar is gone and a `Draft` folder holds its own `container.smd` that no root names
- **THEN** the walk reports `warning: Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd: a sidecar nothing references` and `warning: Doctor Who (1963)/Draft/container.smd: a sidecar nothing references`, in that order

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`theFirstPlacementMakesTheTree`,
`theWalkReportsWhatIsBrokenOrAbandoned`). The recorded modification time and size, and the
id-mismatch and unreadable branches, are pinned by nothing yet.

### Requirement: The validator reports findings at two severities and resolves none
Every check a sidecar has to pass SHALL be reported as a finding: a severity — `error`, a fact a
client would be misled by, or `warning`, one a person should know — plus the sidecar or file the
finding is about, relative to the library root, and the text; the validator SHALL never resolve
one. The checks needing nothing but the value SHALL flag as errors: an item id used twice or not a
slug; an alternative playing a sequence that is not there; a default alternative that is not there;
a presentation for an item the container does not have; two presentations of one item for the same
alternative and profile; a presentation naming an alternative that is not there; a `file=` that
leaves the container's folder; a track for a feature that is not there; a track that names no
stream; an audio or subtitle index below one; and a chapter index repeated or below one. The one
warning at this level SHALL be a file not named as the layout would name it. Against the disk, and
only for paths that stay inside, the validator SHALL flag as errors every file a sidecar names that
is not there (`item <id>: "<file>" is not there`) and every child path that is not there
(`child <id> at "<path>" is not there`). Checking a tree SHALL add what the walk itself found.

#### Scenario: a twice-recorded presentation with an escaping file
- **WHEN** item `part1`'s sidecar records `<presentation file="../Part One.mkv">` and then a second unqualified presentation of the default alternative
- **THEN** the value checks yield exactly `item part1: "../Part One.mkv" leaves the container's folder`, `item part1: "../Part One.mkv" is not the name the layout would give it, "Part One.mkv"` and `item part1 has two presentations for the same alternative and profile`

#### Scenario: the disk checks
- **WHEN** `01 - Season 13/container.smd` was deleted under a walked tree
- **THEN** checking the tree appends to the walk's findings `error: Doctor Who (1963)/container.smd: child 0000000000000002 at "01 - Season 13/container.smd" is not there`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`theWalkReportsWhatIsBrokenOrAbandoned`,
`whatCannotBePlacedIsRefusedWithReasons`, `theFirstPlacementMakesTheTree`). The duplicate-id,
missing-default-alternative, chapter and no-stream checks are pinned by nothing yet.

### Requirement: A folder not named as the layout would name it is a warning
The walk SHALL warn of a container's folder whose name is not the one the layout would give the
container from its sidecar now — its display title, sanitised, after its position among its parent's
children for a container held as a child — as
`folder "<name>" is not the name the layout would give it, "<expected>"`, on the container's
sidecar. The walk SHALL NOT rename it.

#### Scenario: a year corrected after the folder was made
- **WHEN** a film's folder is `Alien (1997)` and its sidecar's year is 1979
- **THEN** the walk warns on `Alien (1997)/container.smd` that the folder is not the name the
  layout would give it, `Alien (1979)`, and the folder is where it was

#### Scenario: a season's folder renamed by hand
- **WHEN** a series' folder holds its only season as `Season 13`
- **THEN** the walk warns that the folder is not the name the layout would give it, `01 - Season 13`, and the folder is where it was

Pinned by: `Tests/SiloStoreTests/IndexTests.swift` (`aFolderNotNamedAsTheLayoutWouldNameItIsAWarning`).
