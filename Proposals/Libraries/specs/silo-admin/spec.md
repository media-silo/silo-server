<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The console shows a silo's settings, and changes what routes may change
For a silo classified with access, SiloAdmin SHALL show the settings `GET /v1/settings` reports. The
name, the embedded node and advertising SHALL be editable through `PATCH /v1/settings`; the
libraries SHALL be managed as the libraries requirement below sets out; and the `silo.json` settings
and the state directory SHALL be shown read-only, as facts of the silo's machine. A refusal from the
silo SHALL be shown in words, naming the reason the silo gave.

#### Scenario: the machine's facts are read-only
- **WHEN** the operator opens a silo's settings
- **THEN** its host, port and state directory are shown and cannot be edited, and its name,
  embedded node and advertising can

#### Scenario: an edit applies without a restart
- **WHEN** the operator turns the embedded node on from the console
- **THEN** the patch is sent, and the settings shown are the ones the silo answered with

Pinned by: nothing yet.

## ADDED Requirements

### Requirement: The console shows a silo's libraries, and adds and removes them within the roots
For a silo classified with access, SiloAdmin SHALL show each library with its path, whether it is
available, when it was last walked, and the findings of that walk. It SHALL add a library through
`POST /v1/libraries`, offering the silo's library roots as the places to choose within, and with no
roots configured SHALL say that the silo has none rather than offer a path the silo will refuse. It
SHALL remove a library through `DELETE /v1/libraries/{library}`, and a refusal SHALL be shown in words.
The console SHALL offer no way to start a walk.

#### Scenario: an unavailable library is shown as such
- **WHEN** the operator opens the libraries of a silo whose `films` folder is missing
- **THEN** `films` is shown unavailable, with when it was last walked

#### Scenario: no roots, no picker
- **WHEN** the operator goes to add a library to a silo with no library roots
- **THEN** the console says the silo has no library roots, rather than offering a path

Pinned by: nothing yet.
