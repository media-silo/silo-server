<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A library may name its ruleset
Each library in `settings.json` MAY carry `ruleset`, the name of a ruleset the silo holds: the
library's standard, which an assignment naming no ruleset is resolved against. A library without
one has no standard. `PUT /v1/libraries/{library}/ruleset`, behind the operator gate, SHALL set or,
with a null name, clear it, written through to `settings.json` and applied at once; a name the silo
holds no ruleset under SHALL be 404 and change nothing.

#### Scenario: a library's standard is set
- **WHEN** the operator sets library `films`'s ruleset to `household`
- **THEN** `settings.json` names `household` for `films`, and the next assignment into `films` that
  names no ruleset is resolved against `household`

Pinned by: nothing yet.
