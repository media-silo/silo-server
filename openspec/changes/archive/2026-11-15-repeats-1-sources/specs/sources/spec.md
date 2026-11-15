<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A source is registered with its input spec, and the silo mints its id
`POST /v1/sources` with an input spec, a natural key, and an optional copy SHALL register
a source and answer 201 with it: an `id` the silo mints, a lowercased UUID; the input spec as given;
the natural key; and its copies. A request without a natural key SHALL be 400, and register nothing.
An input spec the silo refuses, as
[input-specs](../input-specs/spec.md) describes, SHALL be 400 with the reason, and register
nothing. The route SHALL be behind the operator's token. The silo SHALL keep each source as one JSON
file under its state directory, so the sources it has survive a restart.

#### Scenario: a source registered
- **WHEN** the operator registers a source with a valid input spec, a natural key and a copy on node
  `ripper`
- **THEN** the answer is 201 with a minted id, the spec, the key, and one copy on `ripper`

#### Scenario: a source the spec refuses
- **WHEN** the operator registers a source whose input spec repeats a stream index
- **THEN** the answer is 400 naming the index, and no source is registered

#### Scenario: a source without a natural key
- **WHEN** the operator registers a source with a valid input spec and no natural key
- **THEN** the answer is 400, and no source is registered

Pinned by: `Tests/SiloStoreTests/SourceStoreTests.swift` (`aSourceIsRegisteredWithAMintedID`, `sourcesSurviveARestart`), `Tests/SiloTests/ServerTests.swift` (`sourcesAreRegisteredOnceAndTheirCopiesKept`).

### Requirement: A natural key finds the source already registered
A natural key SHALL be a `scheme` and a `value`, both text, unique among the silo's sources. A producer
that knows no identity of its own for a file MAY give its content hash, as scheme `sha256` and the
file's SHA-256 in lowercase hexadecimal.
Registering a source whose natural key matches one the silo has SHALL answer 200 with the existing
source, taking the copy given as a copy is added, so that a registration sent again is answered with
the source the first made; registering one whose natural
key matches but whose input spec differs SHALL be 409, changing nothing.

#### Scenario: the same disc title twice
- **WHEN** a source is registered with natural key scheme `discTitle` and value `3F1AC2E9/00004`, and
  registered again with the same key and spec and a copy on another node
- **THEN** the second answer is 200 with the first source's id, which now has both copies

#### Scenario: the same key, a different description
- **WHEN** a source is registered again with a matching natural key and an input spec with one more
  audio stream
- **THEN** the answer is 409, and the source is as it was

#### Scenario: a registration sent again
- **WHEN** a source is registered with a content hash as its natural key, and the same request is sent
  again
- **THEN** the first answer is 201 and the second 200 with the same source, and the silo holds one
  source

Pinned by: `Tests/SiloStoreTests/SourceStoreTests.swift` (`aNaturalKeyFindsTheSourceAlreadyRegistered`, `theSameKeyDescribedOtherwiseIsRefused`, `twoKeysAreTwoSources`), `Tests/SiloTests/ServerTests.swift` (`sourcesAreRegisteredOnceAndTheirCopiesKept`).
