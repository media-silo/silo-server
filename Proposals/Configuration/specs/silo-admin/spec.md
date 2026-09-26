<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The console shows a silo's settings, and says where each came from
For a silo classified with access, SiloAdmin SHALL show the settings `GET /v1/settings` reports.
Stored settings the environment does not pin SHALL be editable — the name, the embedded node and
advertising through `PATCH /v1/settings`, the libraries through `POST` and `DELETE /v1/libraries` —
and a pinned setting SHALL be shown read-only with the variable that pins it named. Local settings,
the state directory among them, SHALL be shown read-only. Adding a library SHALL offer the silo's
library roots as the places to choose within, and with no roots configured SHALL say that the silo
has none rather than offer a path the silo will refuse. A refusal from the silo SHALL be shown in
words, naming the variable or the reason the silo gave.

#### Scenario: a pinned setting is read-only and says why
- **WHEN** the operator opens the settings of a silo booted with `SILO_LIBRARIES` set
- **THEN** its libraries are shown read-only, set by `SILO_LIBRARIES` on the server, and no add or
  remove is offered

#### Scenario: an edit applies without a restart
- **WHEN** the operator turns the embedded node on from the console
- **THEN** the patch is sent, and the settings shown are the ones the silo answered with

#### Scenario: no roots, no picker
- **WHEN** the operator goes to add a library to a silo with no library roots
- **THEN** the console says the silo has no library roots, rather than offering a path

Pinned by: nothing yet.
