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

### Requirement: silo-ctl encode resolves, shows, runs and verifies one file

`silo-ctl encode` SHALL encode one file from one ruleset with no server: it takes `--ruleset
<path>` (required), an optional `--input <json file>` holding the input's input spec, an optional
`--profile` naming which of the ruleset's outputs to make — the unqualified one when left out — and
the binding as the command line knows it — `--kind`, `--format dvd|bluray|uhd`, the medium the
plain-file producer cannot know, and
repeatable `--commentary`, `--descriptive` and `--music` stream numbers counted from one among
audio, of which commentary and music also map the features `commentary` and `music` — then the
positional input and output paths, the output required unless `--dry-run` is given. Without
`--input` it SHALL describe the input with the plain-file producer. A `--profile` the ruleset has no
output for SHALL be refused, naming the outputs it has. It SHALL then derive the facts,
resolve the recipe and print the decision before anything is encoded: the ruleset's name, one line
per decision as `<kind> <index>  <facts> -> copy|drop|encode <codec> (<rule>)` with the output
placement `=> <kind> <n>` for kept streams, then the feature map as `track <feature> -> audio <n>`
lines with the track indices renumbered to the output — or, with `--json`, the recipe as
pretty-printed JSON. Fact hints SHALL print as `hint:` lines and the recipe's warnings as
`warning:` lines. A stream no rule decides SHALL print the hints and `error: no rule decides …` to
standard error and exit failing. Then — unless `--dry-run` — it SHALL run the encode with a
progress line on standard error, re-probe the output, verify it against the layout and print
`layout verified: <n> streams as the recipe promised`, or print each `layout mismatch:` to standard
error and exit failing.

#### Scenario: dry run shows the recipe and encodes nothing
- **WHEN** `silo-ctl encode --ruleset Examples/household.xml --kind featurette --dry-run in.mkv` runs
- **THEN** the input is described by the plain-file producer, the decision table prints, and no
  output path is required and no encode happens

#### Scenario: the output is required to encode
- **WHEN** the command runs without `--dry-run` and without an output path
- **THEN** it is refused with "an output path is required unless --dry-run is given"

#### Scenario: the layout does not come back as promised
- **WHEN** verification finds a mismatch after the encode
- **THEN** each mismatch prints as a `layout mismatch:` line and the command exits failing

#### Scenario: a spec from another producer
- **WHEN** the command runs with `--input spec.json` naming a spec whose second audio stream is
  marked `commentary`
- **THEN** that stream's role is commentary, and the file is not probed to describe it

Pinned by: nothing yet.

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

Pinned by: nothing yet.
