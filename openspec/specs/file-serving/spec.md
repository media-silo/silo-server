<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# File serving

## Purpose

Files stay where they are until they are placed, and every participant serves the files it holds:
the ingestion tool serves its rips, a node serves its outputs, the silo serves the library. This
spec covers the two halves of that transfer — a holder's file server, which answers a published
file by HTTP `Range` to whoever carries the file's secret, and the fetching side, which resumes by
offset from what it already has. The secret is minted per file by the file's holder, travels to
the silo inside the job's file reference, and reaches the node that claimed the job inside the
claim's answer; the silo relays it and never mints it (the proposal gives the minting to the silo —
the code puts the mint on the holder, in `FileRef.mintSecret`). Plaintext HTTP on a household
network is accepted in this version.

Rationale: [Silo proposal — Files move once](../../../Proposals/Silo.md) — principle 6, every participant serving its own.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: A holder publishes each file under a path, guarded by a secret minted per file
The file server SHALL be plaintext HTTP/1.1 on swift-http-server with one handler and no
framework, bound to a configured host and port — an ephemeral port when 0 is configured, which the
server SHALL answer back once serving — while advertising the host other machines reach it as.
`publish` SHALL place a file under a path of the holder's choosing and return a file reference:
the URL `http://<advertised host>:<port>/files/<path>`, the file's local path for the holder's own
use, the size read from disk, and the secret, which defaults to 64 lowercase hex characters minted
fresh per call. `unpublish` SHALL withdraw a path, and `published` SHALL list the paths held.

#### Scenario: publishing a rip
- **WHEN** a holder publishes a 5000-byte file at `job-1/source`
- **THEN** the returned reference carries the served URL, the path, `sizeBytes` 5000 and the
  secret, and `published` is `["job-1/source"]`

Pinned by: `Tests/SiloTests/FileServerTests.swift` (`aPublishedFileIsFetchedByRangeWithItsSecretAndByNothingElse`).

### Requirement: A request without the file's secret is a 404, not a 401
The handler SHALL answer GET and HEAD on `/files/<path>` only when the `x-silo-secret` header
equals the published secret, and SHALL answer 404 to everything else — a wrong secret, no secret,
an unknown path, a withdrawn path — so that the set of paths cannot be told from the set of
secrets.

#### Scenario: nothing without the secret
- **WHEN** a published file is asked for with a wrong secret, with no secret, at a path that was
  never published, and after its path is unpublished
- **THEN** each answer is 404

Pinned by: `Tests/SiloTests/FileServerTests.swift` (`aPublishedFileIsFetchedByRangeWithItsSecretAndByNothingElse`).

### Requirement: A file is answered whole, by range, or with 416
A published file SHALL be sent through the one response every participant shares — the node's
file server and the silo's media route alike — with `Accept-Ranges: bytes`, an `ETag` of the file
size and modification time, a content type of `video/x-matroska` for `.mkv`, `video/mp4` for
`.mp4` and `.m4v`, `application/octet-stream` otherwise, and always the content length. No `Range`
SHALL be 200 with the whole file; a satisfiable range SHALL be 206 with a `Content-Range` naming
the bytes sent; a range the file cannot satisfy SHALL be 416 with `Content-Range:
bytes */<size>`; HEAD, or a zero-length answer, SHALL be headers only; the bytes SHALL be streamed
a mebibyte at a time. A published file that can no longer be read SHALL be 404.

#### Scenario: whole, part, and beyond the end
- **WHEN** a 3000-byte file is asked for whole, for `bytes=100-199`, for `bytes=2900-`, for
  `bytes=-10`, and for `bytes=5000-`
- **THEN** the answers are 200 and the file, 206 with `Content-Range: bytes 100-199/3000`, 206
  with the last hundred bytes, 206 with `Content-Range: bytes 2990-2999/3000`, and 416 with
  `Content-Range: bytes */3000`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`mediaIsServedWholeAndByRange`), `Tests/SiloTests/FileServerTests.swift` (`aPublishedFileIsFetchedByRangeWithItsSecretAndByNothingElse`). The unreadable-file 404 is pinned by nothing yet.

### Requirement: A Range header is one range or the whole file
`bytes=a-b`, `bytes=a-` and `bytes=-n` SHALL be honoured, one range at a time; an end past the
file SHALL be clipped to the last byte; a start at or past the size SHALL be unsatisfiable; a
suffix longer than the file SHALL mean all of it; a header of several ranges, or of another unit,
or anything unparsable SHALL be treated as asking for the whole file.

#### Scenario: the specification's own cases, on a 100-byte file
- **WHEN** the header is, in turn, absent, `bytes=0-49`, `bytes=50-`, `bytes=-10`, `bytes=0-500`,
  `bytes=100-`, `bytes=0-1,5-6`, and `items=0-1`
- **THEN** the range is the whole file, bytes 0–49, bytes 50–99, bytes 90–99, bytes 0–99 (clipped),
  unsatisfiable, the whole file, and the whole file

Pinned by: `Tests/SiloTests/ServerTests.swift` (`rangesAreParsedAsTheSpecificationSays`).

### Requirement: A fetch resumes by offset from what is already on disk
The fetching side SHALL send the file's secret as `x-silo-secret`; SHALL, when bytes of the
destination already exist, ask `Range: bytes=<existing>-` and append; SHALL, when the holder
ignores that range and answers 200, truncate and start over rather than append; SHALL accept only
200 and 206, treating any other status as the failure `the holder answered <status>`; SHALL skip
the fetch entirely when the file on disk already has the reference's recorded size; and SHALL,
when the reference records a size, verify the fetched file has it, failing with `got <final> bytes
of <size>` when it does not.

#### Scenario: resuming an interrupted fetch
- **WHEN** 1234 bytes of a 5000-byte file are already on disk and the fetch runs
- **THEN** the holder is asked from byte 1234 and the file on disk afterwards equals the
  published file byte for byte

Pinned by: `Tests/SiloTests/FileServerTests.swift` (`aPublishedFileIsFetchedByRangeWithItsSecretAndByNothingElse`).
