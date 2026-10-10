<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The console shows a silo's rulesets, their branches and versions, and the silo's reading of each
For a silo classified with access, SiloAdmin SHALL show each ruleset the silo holds, and for a ruleset
its branches — each with its base, its head, the standard version it is up to date with, and whether it
has been promoted — and its versions on each, with the number of placed presentations each made. For a
version it SHALL show the document as the silo stored it, comments and all, and beside it the silo's
reading: the extraction policy, the rules grouped by scope in document order within each, each by the
name a recipe calls it by with its conditions and action, and the outputs. A scope whose last rule has
conditions SHALL be marked as having no catch-all. The console SHALL draw the reading from the silo
and SHALL NOT read a ruleset's XML itself. The section SHALL keep itself current as the rest of the
console does.

#### Scenario: a ruleset opened
- **WHEN** the operator opens a ruleset whose standard's head is version 3
- **THEN** version 3's document is shown as stored, beside the silo's reading of it, and the branches
  and their versions can be chosen

#### Scenario: a scope that can stop an application
- **WHEN** a version's audio rules all have conditions
- **THEN** the audio scope is marked as having no catch-all

Pinned by: nothing yet.

### Requirement: The console shows a library's out-of-date presentations
For each library of a silo classified with access, SiloAdmin SHALL show its out-of-date presentations
as the silo's report gives them — each with its container and item, the stack that made it and the
stack it was checked against, the streams that would change from what to what, and whether every
source of its binding has a copy — and how many of the library's presentations are still to be
checked. It SHALL make nothing again.

#### Scenario: a check under way
- **WHEN** the silo's background check has twelve presentations still to check in a library
- **THEN** the library shows the out-of-date presentations found so far, and says twelve are still to
  be checked

Pinned by: nothing yet.
