<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A container's artwork is read, put and removed by kind
The `LibraryContainer` a library's container route answers SHALL carry `artwork`, the kinds the
container's folder holds, read from the folder when asked rather than from the index.
`GET /v1/libraries/{library}/containers/{id}/artwork/{kind}` SHALL answer 200 with the kind's
image and its content type, or 404 when the folder holds none; it is a read route, and SHALL
answer without a token. `PUT` on the same path SHALL take the image's bytes and SHALL accept a
JPEG or a PNG, told by the bytes' signature rather than the declared type: anything else SHALL be
415, and an image over 25 MB SHALL be 413. It SHALL write the file as `<kind>.jpg` or
`<kind>.png` by writing beside it and renaming, SHALL remove the kind's file in the other format
if there is one, and SHALL answer 200 with the kind and its format. `DELETE` on the same path
SHALL remove the kind's file and answer 204, or 404 when there is none. A kind that is not one of
the artwork kinds, a library the silo does not serve, and a container it does not hold SHALL be
404. `PUT` and `DELETE` SHALL require the operator's bearer; a missing or wrong bearer SHALL be
401.

#### Scenario: a poster put and served
- **WHEN** the operator puts a JPEG as a container's `poster`
- **THEN** the answer is 200, the container's `artwork` includes `poster`, and getting the
  poster answers the same bytes as `image/jpeg`

#### Scenario: a PNG replaces a JPEG
- **WHEN** the operator puts a PNG as the `poster` of a container whose folder holds
  `poster.jpg`
- **THEN** the folder holds `poster.png` and no `poster.jpg`

#### Scenario: a file that is not an image
- **WHEN** the operator puts a text file as a `poster`
- **THEN** the answer is 415, and the folder is unchanged

#### Scenario: a poster removed
- **WHEN** the operator deletes a container's `poster`
- **THEN** the answer is 204, the folder holds no poster, and getting the poster is 404

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aContainersArtworkIsPutServedAndRemoved`).
