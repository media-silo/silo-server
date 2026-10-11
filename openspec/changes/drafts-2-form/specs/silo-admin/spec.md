<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A draft is edited in a form built from the rule language
SiloAdmin SHALL edit a draft in a form: rules added, edited, deleted, and dragged to reorder within
their scope; outputs added, edited and deleted. A condition's fact SHALL be chosen from the rule
language's facts, offering only the tests the fact takes and, where the fact's values are a closed
set, only those values; an action SHALL be copy, drop, or an encode with its settings as fields. Every
change SHALL be made by splicing the draft's text, so the text view shows exactly what changed. While
the text cannot be read, the form SHALL show the reader's refusal and make no change.

#### Scenario: a rule moved in the form
- **WHEN** the operator drags the commentary rule above the lossless rule
- **THEN** the text shows the rule moved with its comment, and no other difference

#### Scenario: a fact's tests
- **WHEN** the operator adds a condition on `audio.channels`
- **THEN** the form offers the seven tests, and for `audio.role` only `is`, `ne` and `in`, with its
  roles as the values

Pinned by: nothing yet.
