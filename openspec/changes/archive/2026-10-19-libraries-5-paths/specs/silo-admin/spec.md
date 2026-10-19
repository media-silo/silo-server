<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The console shows a silo's libraries, and adds and removes them within the roots
For a silo classified with access, SiloAdmin SHALL show each library with its path, whether it is
available, when it was last walked, and the findings of that walk, and with the ruleset that is its
standard, which the operator MAY name or clear through `PUT /v1/libraries/{library}/ruleset`. The
section SHALL read the libraries and their walks again at the console's cadence while it is open.
It SHALL add a library through `POST /v1/libraries`, offering the silo's library roots as the places
to choose within, and when the roots are empty SHALL say that the silo has none rather than offer a
path the silo will refuse. While the operator names a folder, it SHALL ask
`POST /v1/libraries/check` and show the path, in a sentence saying whether a library will be created
there, with the part that exists told apart from the part that does not: the missing folders as
refused while nothing asks for them to be made, and as to be made once the operator asks and the
silo would make them, saying how many; a path whose folders all exist SHALL be said to exist. Any
other refusal of the path SHALL be given in that sentence in the silo's words, and a refusal of the
name, which leaves the path good, SHALL be shown apart from it in the silo's words. When folders are missing it SHALL offer
to make them, and SHALL send `create` only when the operator has asked for them to be made. It SHALL
remove a library through `DELETE /v1/libraries/{library}`, and a refusal SHALL be shown in words.
The console SHALL offer no way to start a walk.

#### Scenario: an unavailable library is shown as such
- **WHEN** the operator opens the libraries of a silo whose `films` folder is missing
- **THEN** `films` is shown unavailable, with when it was last walked

#### Scenario: a library's standard named
- **WHEN** the operator names `household` as a library's standard from the console
- **THEN** the route is sent, and the library shows the standard the silo answered with

#### Scenario: empty roots, no picker
- **WHEN** the operator goes to add a library to a silo whose library roots are an empty list
- **THEN** the console says the silo has no library roots, rather than offering a path

#### Scenario: missing folders shown, and made when asked
- **WHEN** the operator names a folder within a root, two of whose folders do not exist
- **THEN** the console shows the path with both apart from the part that exists, says a library
  cannot be created there because the two folders do not exist, and once the operator asks for them
  to be made says a library will be created there and the two folders made; the addition sends
  `create` only then

#### Scenario: a name already taken leaves the path good
- **WHEN** the operator names a folder that exists, for a library whose name the silo already has
- **THEN** the console says a library will be created at the path, which exists, and shows apart from
  it the silo's refusal of the name

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`librariesAreAddedAndRemovedFromTheConsole`,
`aLibrarysStandardIsNamedFromTheConsole`, `aLibrarysPathIsCheckedAndItsFoldersMadeFromTheConsole`),
`Tests/SiloAdminTests/ConsoleModelTests.swift` (`anUnavailableLibraryIsShownWithItsLastWalk`,
`theLibrariesSectionKeepsItselfCurrent`, `aLibrarysStandardShowsWhatTheSiloAnswered`,
`withTheRootsEmptiedTheConsoleSaysSoAndShowsTheRefusal`), `Tests/SiloTests/ServerTests.swift`
(`theConsolesTypesReadTheSilosAnswers`), which pin the engine, the model the pane is drawn from and
the console's types against the silo's answers; the pane itself is pinned by nothing yet.
