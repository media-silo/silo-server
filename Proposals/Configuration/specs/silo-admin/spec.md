<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The console shows a silo's settings, and changes what routes may change
For a silo classified with access, SiloAdmin SHALL show the settings `GET /v1/settings` reports. The
`settings.json` settings SHALL be editable — the name, the embedded node and advertising through
`PATCH /v1/settings`, the libraries through `POST` and `DELETE /v1/libraries` — and the `silo.json`
settings and the state directory SHALL be shown read-only, as facts of the silo's machine. Adding a
library SHALL offer the silo's library roots as the places to choose within, and with no roots
configured SHALL say that the silo has none rather than offer a path the silo will refuse. A refusal
from the silo SHALL be shown in words, naming the reason the silo gave.

#### Scenario: the machine's facts are read-only
- **WHEN** the operator opens a silo's settings
- **THEN** its port, library roots and state directory are shown and cannot be edited, and its
  name, libraries, embedded node and advertising can

#### Scenario: an edit applies without a restart
- **WHEN** the operator turns the embedded node on from the console
- **THEN** the patch is sent, and the settings shown are the ones the silo answered with

#### Scenario: no roots, no picker
- **WHEN** the operator goes to add a library to a silo with no library roots
- **THEN** the console says the silo has no library roots, rather than offering a path

Pinned by: nothing yet.
