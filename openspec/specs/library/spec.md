<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Library

## Purpose

A library is one folder tree of smd-shaped containers: every container that owns files is a folder
named from its display title, nesting as the container tree nests, with `container.smd` inside and
each presentation's file beside it. This spec fixes that layout and its name rules, the id a
sidecar's container carries, how `<track>` indices count, the walk that finds every sidecar from
the roots down and reports what nothing references, and the validator's checks with their
error/warning severities.

Rationale: [Silo proposal — The library on disk](../../../Proposals/Silo.md) — the layout, the
container id and the track-counting rule, fixed there for the routes and the validator.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: A container that owns files is a folder named from its display title
Every container that owns files SHALL live in a folder inside its parent's folder, named for the
container's display title, and a library's roots SHALL be its top-level folders. Every such folder
SHALL hold one file named `container.smd`, and a parent's sidecar SHALL record each child as the
child's folder followed by `/container.smd` (for example `Season 13/container.smd`) on the child's
`<item type="container">`. A title becomes a folder or file name sanitised: `/` and `:` replaced by
`-`, NUL dropped, runs of whitespace collapsed to one space, leading dots removed and the result
trimmed. A display title that sanitises to nothing SHALL fall back to the container id's raw value.

#### Scenario: titles are sanitised for the filesystem
- **WHEN** display titles are `Doctor Who: The Movie`, `  Face/Off  `, `..hidden` and a title with runs of spaces and tabs
- **THEN** the names are `Doctor Who- The Movie`, `Face-Off`, `hidden` and the whitespace collapsed to single spaces

#### Scenario: slashes become dashes
- **WHEN** a container's title is `///`
- **THEN** its folder name is `---` — each solidus replaced — not the container id

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`namesAreSanitised`,
`pathsAreCheckedForStayingInside`). The fall-back to the container id after sanitising to nothing
is pinned by nothing yet.

### Requirement: A presentation's file is `{item} - {display name}.mkv` beside its sidecar
The file for a presentation of an item SHALL sit in the item's container's folder, beside
`container.smd`, named `{item} - {display name}.{extension}`, or `{item}.{extension}` when there is
no display name. `{item}` is the item's title, sanitised, or its id when the item has none. The
display name SHALL be the presentation's alternative's title — the alternative's id when it has no
title — or its profile when it has no alternative, and nothing for the unqualified presentation of
the default alternative. An item the container lists as an extra SHALL live at
`extras/{item} - {display name}.{extension}` in `extras/` inside the owning container's folder. A
sidecar SHALL record the path relative to the folder holding the sidecar, and a
`PlacementRequest`'s presentation SHALL have its `file=` ignored: the layout decides the name.

#### Scenario: the unqualified presentation of the default alternative
- **WHEN** `part1` of Pyramids of Mars, titled `Part One`, is placed with no alternative and no profile
- **THEN** the recorded `file=` is `Part One.mkv`

#### Scenario: a profile names the file
- **WHEN** the same item is placed with `profile="mobile"`
- **THEN** the recorded `file=` is `Part One - mobile.mkv`

#### Scenario: an alternative's title names the file
- **WHEN** the same item is placed as the `se` alternative, titled `Updated special effects`
- **THEN** the recorded `file=` is `Part One - Updated special effects.mkv`

#### Scenario: an extra lives under `extras/`
- **WHEN** the extra `now-and-then`, titled `Now and Then: Pyramids`, is placed
- **THEN** the recorded `file=` is `extras/Now and Then- Pyramids.mkv` and the `extras/` folder is created inside the serial's folder

#### Scenario: an item without a title names its id
- **WHEN** an item has id `part1` and no title
- **THEN** its file name is `part1.mkv`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`theFirstPlacementMakesTheTree`,
`aSecondPlacementUpdatesOnlyWhatChanged`, `pathsAreCheckedForStayingInside`).

### Requirement: A path a sidecar names stays inside its container's folder
Every path a sidecar names — a presentation's `file=` and a child's `smd=` — SHALL be relative to
the folder holding the sidecar and SHALL NOT leave that container's folder: not empty, not
absolute, and with no `..` and no empty component (`LibraryLayout.isInside`). A container's folder
is the unit that is moved, backed up and re-pointed. The validator SHALL flag a presentation's
`file=` that escapes as an error (`"<file>" leaves the container's folder`) and SHALL flag a
`file=` that is not the name the layout would give the presentation as a warning
(`"<file>" is not the name the layout would give it, "<expected>"`); the walk SHALL refuse a child
whose `smd=` is not a sidecar inside the parent's folder, as an error
(`child <id> is at "<path>", which is not a sidecar inside this folder`).

#### Scenario: paths that stay inside and paths that do not
- **WHEN** paths are checked against `isInside`
- **THEN** `Part One.mkv` and `extras/Now.mkv` stay inside, and `../Part One.mkv`, `extras/../../x.mkv`, `/abs.mkv`, `` and `a//b.mkv` do not

#### Scenario: an escaping file is an error beside its warning
- **WHEN** item `part1`'s sidecar records `<presentation file="../Part One.mkv">`
- **THEN** the findings include the error `item part1: "../Part One.mkv" leaves the container's folder` and the warning `item part1: "../Part One.mkv" is not the name the layout would give it, "Part One.mkv"`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`pathsAreCheckedForStayingInside`,
`theWalkReportsWhatIsBrokenOrAbandoned`).

### Requirement: A sidecar names its container by the minted `ContainerID`
A library sidecar SHALL carry the container id exactly as the repository file does: the minted
`ContainerID`, sixteen lowercase hexadecimal characters — item, sequence, alternative and feature
ids stay slugs, local to the container. A sidecar whose container id is anything else, a
hand-authored slug included, SHALL fail to parse; the walk SHALL report that sidecar as an
error-severity finding (`unreadable: …`) and drop it from the tree rather than refuse the library —
a slug is reported, not refused. An item id that is not a slug SHALL be an error-severity finding
(`item id <id> is not a slug`), as SHALL an item id used twice (`item id <id> is used twice`).

#### Scenario: a slug for a container id
- **WHEN** a sidecar on disk names its container `pyramids` rather than sixteen hexadecimal characters
- **THEN** the walk reports an error for that `container.smd` and the container is not in the tree, while the rest of the library is still read

Pinned by: nothing yet. (The id checks and the walk's unreadable branch are not under test.)

### Requirement: `<track>` indices count from one among streams of their kind
A `<track>` element SHALL number its stream from one among the streams of that kind in the file it
describes — the way a player's audio menu counts, and the way a re-encode that dropped a stream
renumbers — never by the file's absolute stream position: `audio="2"` names the file's second audio
stream. An `audio` or `subtitle` below one SHALL be an error-severity finding
(`audio streams count from one; <feature> is at <n>`), and a `<track>` that names neither SHALL be
an error-severity finding (`a track for <feature> that names no stream`).

#### Scenario: output-numbered tracks validate cleanly
- **WHEN** a serial declares feature `commentary1` and two presentations are placed — the full file with `<track feature="commentary1" audio="3"/>`, the mobile re-encode that dropped the surround mix with `audio="2"`
- **THEN** the validator reports nothing for them

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`theFirstPlacementMakesTheTree`,
`aSecondPlacementUpdatesOnlyWhatChanged`). The below-one and no-stream findings are pinned by
nothing yet.

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
- **WHEN** `Doctor Who (1963)/Season 13/Pyramids of Mars` was placed with one presentation
- **THEN** the walk yields one root, finds the serial at the relative folder `Doctor Who (1963)/Season 13/Pyramids of Mars`, and reports no findings

#### Scenario: a child sidecar that does not exist is an error
- **WHEN** `Doctor Who (1963)/Season 13/container.smd` was deleted
- **THEN** the walk reports `error: Doctor Who (1963)/container.smd: child 0000000000000002 is at "Season 13/container.smd", which does not exist`

#### Scenario: sidecars nothing references are warnings
- **WHEN** the season's sidecar is gone and a `Draft` folder holds its own `container.smd` that no root names
- **THEN** the walk reports `warning: Doctor Who (1963)/Draft/container.smd: a sidecar nothing references` and `warning: Doctor Who (1963)/Season 13/Pyramids of Mars/container.smd: a sidecar nothing references`, in that order

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
- **WHEN** `Season 13/container.smd` was deleted under a walked tree
- **THEN** checking the tree appends to the walk's findings `error: Doctor Who (1963)/container.smd: child 0000000000000002 at "Season 13/container.smd" is not there`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`theWalkReportsWhatIsBrokenOrAbandoned`,
`whatCannotBePlacedIsRefusedWithReasons`, `theFirstPlacementMakesTheTree`). The duplicate-id,
missing-default-alternative, chapter and no-stream checks are pinned by nothing yet.
