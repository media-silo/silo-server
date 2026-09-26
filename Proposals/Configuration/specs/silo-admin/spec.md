<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The console shows a silo's settings, and changes what routes may change
For a silo classified with access, SiloAdmin SHALL show the settings `GET /v1/settings` reports. The
name, the embedded node and advertising SHALL be editable through `PATCH /v1/settings`, and the
`silo.json` settings and the state directory SHALL be shown read-only, as facts of the silo's
machine. A refusal from the silo SHALL be shown in words, naming the reason the silo gave.

#### Scenario: the machine's facts are read-only
- **WHEN** the operator opens a silo's settings
- **THEN** its host, port and state directory are shown and cannot be edited, and its name,
  embedded node and advertising can

#### Scenario: an edit applies without a restart
- **WHEN** the operator turns the embedded node on from the console
- **THEN** the patch is sent, and the settings shown are the ones the silo answered with

Pinned by: nothing yet.
