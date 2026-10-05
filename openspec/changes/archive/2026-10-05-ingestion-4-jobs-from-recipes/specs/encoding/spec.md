<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: Several segments, or part of one, are one concat input
A recipe run on one whole segment SHALL take that segment's file as its input, as the argument list
describes. A recipe run on several segments, or on a span of one, SHALL take as its one input a
concat list, given as `-f concat -safe 0 -i <list>` in place of `-i <input>`, the list holding a
`file` line for each segment in order and, for a segment with a span, `inpoint` and `outpoint` lines
of its span's start and end in seconds; the rest of the argument list is as for one file, so stream
indices are the joined media's. A stream the recipe copies is cut where the span's points fall on
it, which for a span of chapters is where the source divides itself.

#### Scenario: an episode out of a play-all title
- **WHEN** a recipe runs on one segment spanning 1497.6 to 2995.2 seconds of `title.mkv`
- **THEN** the input is a concat list naming `title.mkv` with `inpoint 1497.6` and `outpoint 2995.2`

#### Scenario: a film across two discs
- **WHEN** a recipe runs on two whole segments, `disc1.mkv` then `disc2.mkv`
- **THEN** the input is a concat list naming `disc1.mkv` then `disc2.mkv`, with no points

Pinned by: `Tests/EncoderTests/ArgumentsTests.swift` (`severalSegmentsOrASpanAreOneConcatInput`), `Tests/SiloTests/JobTests.swift` (`aSpanOfOneHeldSourceAndAWholeFetchedOneAreEncodedAsOneInput`, which encodes a span and a whole source through the list).
