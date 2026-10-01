<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: ffprobe's JSON is reduced to a probed source

`ffprobe` SHALL be run as `-v error -print_format json -show_format -show_streams -show_chapters <file>` and its
output reduced to a `ProbedSource` by a pure function, so the reduction is testable on a captured
document with no `ffprobe` present. `codec_type` maps to the stream kinds video, audio, subtitle,
data and attachment, anything else to `other`; `disposition` entries with a non-zero value become
the stream's set of dispositions; `language` and `title` come from the stream's tags in either
letter-case; the frame rate comes from `avg_frame_rate` then `r_frame_rate`, kept as the fraction
`ffprobe` reports — `30000/1001` stays `30000/1001` — with `0/0` read as no rate at all; each
chapter's start comes from its `start_time` and its title from its tags, in the order `ffprobe`
lists them; the duration comes from the format object.
Output that does not decode SHALL throw `ToolError.unreadableOutput` naming `ffprobe`.

#### Scenario: the document is reduced to what facts need
- **WHEN** a probe document holds an h264 progressive stream tagged `language=eng`, a DTS-HD MA track, an AC-3 track tagged `LANGUAGE=eng` and `TITLE=Commentary` with disposition `comment=1`, a forced PGS subtitle and a ttf attachment
- **THEN** the probed source has five streams with the right kinds and dispositions, reads the upper-case tags, keeps the `DTS-HD MA` profile, and takes the duration 1500.32 from the format

#### Scenario: chapters from the probe
- **WHEN** a probe document lists two chapters starting at 0 and 1497.6 seconds, the first titled `Part One`
- **THEN** the probed source has those two chapters, in that order, the first titled `Part One`

#### Scenario: 0/0 is no rate, not a rate of zero
- **WHEN** a stream reports `avg_frame_rate` `0/0`
- **THEN** its frame rate is nil

#### Scenario: something that is not ffprobe's output
- **WHEN** the output is not JSON
- **THEN** `ToolError.unreadableOutput` is thrown

Pinned by: `Tests/EncoderTests/ProbeParsingTests.swift` (`theDocumentIsReducedToWhatFactsNeed`, `aFractionalRateIsAFraction`, `somethingThatIsNotFFprobesOutputIsRefused`); chapters are pinned by nothing yet.
