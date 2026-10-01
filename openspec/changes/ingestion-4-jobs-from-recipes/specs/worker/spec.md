<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The recipe becomes one encode in the work folder
A claimed job whose answer carries no recipe SHALL fail at once, with
`job <id> has no recipe to run`. Otherwise the worker SHALL clear any stale output and encode the
job's segments — one whole segment as its file, several or a span as one concat input, as
[encoding](../encoding/spec.md) describes — to `<job id>.<the recipe's output extension>` in the
work folder, run with the one argument list the recipe spells for that input and output; ffmpeg's
own progress SHALL become the job's progress, the fraction the seconds done over the recipe's
recorded duration, never above 1.

#### Scenario: the recipe decides the output
- **WHEN** a pending job whose recipe produces an `mkv` is run
- **THEN** the output is `<job id>.mkv` in the work folder, made by the recipe's own arguments

Pinned by: `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`, which
asserts the `<job id>.mkv` name). The not-ready arm is pinned by nothing yet.

## ADDED Requirements

### Requirement: Each of a job's segments is opened where it is or fetched
For each segment the claim hands it, the worker SHALL reach the segment's copy as the requirements
above describe for a source: opened in place when the copy names this node as its holder with a
local path, or is a `file://` URL; otherwise fetched by range into the work folder, as
`<job id>.<n>.source.<ext>` for the segment at position `n` from one, resuming by offset. Two
segments of one source SHALL be reached once.

#### Scenario: two segments, one held and one fetched
- **WHEN** a node claims a job of two segments, holding the first's source and not the second's
- **THEN** it opens the first in place and fetches the second into the work folder

Pinned by: nothing yet.
