<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A library may name its ruleset
Each library in `settings.json` MAY carry `ruleset`, the name of a ruleset the silo holds: the
library's standard, which an application that names no ruleset takes. A library without one has no
standard. `PUT /v1/libraries/{library}/ruleset`, behind the operator's token, SHALL set or, with a
null name, clear it, written through to `settings.json` and applied at once; a library the silo does
not have, or a name it holds no ruleset under, SHALL be 404 and change nothing.

#### Scenario: a library's standard is set
- **WHEN** the operator sets a library's ruleset to `household`
- **THEN** `settings.json` names `household` for that library, and the next application to a
  binding into it that names no ruleset applies `household`

#### Scenario: a ruleset the silo does not hold
- **WHEN** the operator sets a library's ruleset to a name no ruleset is stored under
- **THEN** the answer is 404, and `settings.json` is as it was

Pinned by: nothing yet.
