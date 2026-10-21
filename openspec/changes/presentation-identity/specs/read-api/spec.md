<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A presentation is served as bytes, whole and by range
`GET /v1/media/{presentation}` SHALL take a presentation's id and answer the
file, streaming; an id nothing holds SHALL be 404. The head SHALL carry
`Accept-Ranges: bytes`, an `ETag` of `"<size>-<modification time>"`, the
`Content-Length` and a `Content-Type` from the file's extension — `.mkv` as
`video/x-matroska`, `.mp4` and `.m4v` as `video/mp4`, anything else
`application/octet-stream`. One satisfiable single range — `bytes=a-b`,
`bytes=a-` or `bytes=-n`, an end past the file clipped to the last byte —
SHALL be 206 with `Content-Range: bytes <start>-<end>/<size>`; several ranges,
or a unit that is not `bytes`, SHALL be answered as the whole file; a range
the file cannot satisfy SHALL be 416 with `Content-Range: bytes */<size>`.
HEAD SHALL be answered as the GET's head alone, and the file SHALL go to the
writer a chunk at a time rather than buffered whole. A presentation placed
during the server's run SHALL be served by its new id at once, without a scan
being asked for. A presentation whose file the route finds missing SHALL be
served from the file its container's sidecar records once the route has re-read
it, when that is another file that is there, by the same id; only when the
re-read leaves no file for the id SHALL the answer be 404.

#### Scenario: the whole file
- **WHEN** a client asks `GET /v1/media/{presentation}` for a 3000-byte
  presentation
- **THEN** the answer is 200 with `Accept-Ranges: bytes`,
  `Content-Type: video/x-matroska`, an `ETag`, and the body's bytes are the
  file's

#### Scenario: a part of the file
- **WHEN** the client sends `Range: bytes=100-199`
- **THEN** the answer is 206, `Content-Range: bytes 100-199/3000`, and the
  body is exactly those hundred bytes; `bytes=2900-` answers 206 from byte
  2900 to the end, and `bytes=-10` answers with
  `Content-Range: bytes 2990-2999/3000`

#### Scenario: a range the file cannot satisfy
- **WHEN** the client sends `Range: bytes=5000-`
- **THEN** the answer is 416 with `Content-Range: bytes */3000`, and
  `GET /v1/media/0000000000000000` is 404

#### Scenario: a file moved
- **WHEN** a presentation's file is moved within its container's folder and its
  sidecar edited to name it there, and a client asks for the presentation by the
  id it had before
- **THEN** the answer is 200 with the file from its new path

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`aMovedFileIsServedByTheIdItHad`, `mediaIsServedWholeAndByRange`, `rangesAreParsedAsTheSpecificationSays`,
`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).
