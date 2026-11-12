<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: An image is held by its digest for a store to put
`PUT /v1/blobs/{digest}`, where the digest is the SHA-256 of the image's bytes in lowercase
hexadecimal, SHALL take the image's bytes and SHALL accept a JPEG or a PNG, told by the bytes'
signature, as the artwork route does: anything else SHALL be 415, and an image over 25 MB SHALL be
413. Bytes whose SHA-256 is not the digest named SHALL be 400, and nothing SHALL be held. Otherwise the
silo SHALL hold the bytes under `blobs/` in its state directory, by writing beside them and renaming,
and SHALL answer 204, as it SHALL when it already holds them, writing nothing. `GET` on the same path
SHALL answer 200 with the blob's `digest` and `size` in bytes when the silo holds it, and 404 when it
does not. A put of a blob the silo holds
SHALL begin its day again. A blob that no store under way names SHALL be removed once a day has passed
since it was last put. Both routes SHALL require the
operator's bearer; a missing or wrong bearer SHALL be 401.

#### Scenario: an image held by its digest
- **WHEN** the operator puts a JPEG at the blob route named by its SHA-256
- **THEN** the answer is 204, and asking after the same digest answers 200

#### Scenario: bytes that are not the digest named
- **WHEN** the operator puts a JPEG at the blob route named by another image's SHA-256
- **THEN** the answer is 400, and asking after either digest answers 404

#### Scenario: an image put twice
- **WHEN** the operator puts the same JPEG at its blob route twice
- **THEN** both answers are 204, and the silo holds the image once

#### Scenario: a blob nothing names
- **WHEN** a blob was put more than a day ago, and no store under way names it
- **THEN** the silo no longer holds it, and asking after its digest answers 404

Pinned by: `Tests/SiloTests/ServerTests.swift` (`anImageIsHeldByItsDigestForAStoreToPut`),
`Tests/SiloStoreTests/BlobStoreTests.swift` (`aBlobIsKeptADayUnlessAStoreNamesIt`).
