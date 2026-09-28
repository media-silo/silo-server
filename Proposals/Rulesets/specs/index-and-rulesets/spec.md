<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Every store is a new version the silo numbers, and a version is never rewritten
A store SHALL be assigned the next version for its name — the latest plus one, or 1 for a
new name — read and taken under one lock, so no two stores receive the same number. A store
MAY name the version it expects to be the latest, 0 meaning none; the expectation SHALL be
compared with the latest version under the same lock, and a store whose expectation does not
hold SHALL be refused as `notLatest`, naming the latest version, and SHALL write nothing. A
version SHALL NOT be rewritten: a file already on disk under that version is refused as
`versionExists`. A document SHALL be parsed before it is stored, and a document the reader
refuses SHALL NOT be stored at all. A name that is empty, contains a `/`, or begins with a
`.` SHALL be refused as `invalidName`. Checking a name and a document SHALL take the path a
store takes, without the lock and the write, so a check and a store refuse alike.

#### Scenario: two stores are numbered in order
- **WHEN** the same document is stored as `household` twice
- **THEN** the first store is version 1, the second version 2, and the latest version of
  `household` is 2

#### Scenario: a document that is not a ruleset is refused
- **WHEN** a document testing a fact a rule cannot test — `<when fact="nope" is="1"/>` — is
  stored
- **THEN** it is not stored; over the API the answer is 400 with
  `not a fact a rule can test` in the problem detail

#### Scenario: two stores on one base
- **WHEN** two stores of `household`, each expecting version 2 to be the latest, run at once
- **THEN** one is stored as version 3 and the other is refused as `notLatest` naming version
  3, and there is no version 4

Pinned by: `Tests/SiloTests/ServerTests.swift` (`rulesetsAreVersionedAndTheOperatorGateHolds`).
The `invalidName` and `versionExists` guards, the expected latest and the check are pinned by
nothing yet.
