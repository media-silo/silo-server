<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: ffmpeg and ffprobe are found in a fixed order and run as processes

Each tool SHALL be located by first consulting its environment variable — `FFMPEG_PATH` for
ffmpeg, `FFPROBE_PATH` for ffprobe — which must name an executable file; then the directories of
`PATH` in order; then `/opt/homebrew/bin`, `/usr/local/bin` and `/usr/bin`, so a launchd or GUI
process with the system's `PATH` still finds them. A tool found nowhere SHALL fail with
"`ffmpeg` was not found; set FFMPEG_PATH or put it on PATH" (likewise for `ffprobe`). Both tools
run as child processes whose standard output streams back a line at a time; neither is linked or
wrapped in-process.

#### Scenario: no ffmpeg anywhere
- **WHEN** `FFMPEG_PATH` is unset, no `PATH` entry holds an `ffmpeg`, and none of the three fallback folders does either
- **THEN** constructing the driver throws "ffmpeg was not found; set FFMPEG_PATH or put it on PATH"

Pinned by: nothing yet.

### Requirement: A recipe compiles to one ffmpeg argument list

`Recipe.ffmpegArguments(input:output:)` SHALL be a pure function giving the whole invocation. It
starts `-y -nostdin -hide_banner -loglevel error -progress pipe:1 -nostats -i <input>`, then
emits one `-map 0:<sourceAbsoluteIndex>` per layout stream in layout order, so the output's
stream order is the layout's. Every kept stream's options SHALL be addressed to it by its place
among output streams of its kind — `-c:a:1` is the output's second audio stream, whatever its
source was — using the specifier `v`, `a` or `s` and the zero-based output index. A copied stream
takes `-c:<specifier> copy`; a dropped stream contributes nothing; an encoded stream takes
`-c:<specifier> <codec>` plus `-preset`, `-crf`, `-b`, `-ac` and `-pix_fmt` options for the
settings that are set, its filters joined with commas into one `-filter:<specifier>` argument,
and each free option sorted by name as `-<name>:<specifier> <value>`. Filters SHALL be spelled
`yadif=deint=interlaced` for automatic deinterlacing, `yadif` for always, `scale=<w>:<h>` with
`-2` for an omitted dimension, and a custom filter as its own text. The list SHALL end
`-map_metadata 0 -map_chapters 0 -f matroska <output>`. Only the `mkv`/`matroska` container is
exercised.

#### Scenario: the recipe is the argument list
- **WHEN** a recipe copies the video and subtitle, encodes audio 1 to flac with option `compression_level=8`, encodes audio 2 to aac at 160k stereo, and drops a DTS core
- **THEN** the list maps `0:0 0:1 0:3 0:4`, runs `-c:v:0 copy`, `-c:a:0 flac -compression_level:a:0 8`, `-c:a:1 aac -b:a:1 160k -ac:a:1 2` and `-c:s:0 copy`, and ends `-map_metadata 0 -map_chapters 0 -f matroska <output>`

#### Scenario: a re-encoded video carries its filters
- **WHEN** the small-extras rule encodes a 352x288 interlaced featurette
- **THEN** the video's arguments include `-preset:v:0 slow -crf:v:0 22 -pix_fmt:v:0 yuv420p -filter:v:0 yadif=deint=interlaced`

Pinned by: `Tests/EncoderTests/ArgumentsTests.swift` (`theRecipeIsTheArgumentList`, `aReencodedVideoCarriesItsFilters`).

### Requirement: Progress is reported a block at a time as the encode runs

`ffmpeg` is invoked with `-progress pipe:1`, which writes blocks of `key=value` lines ending in a
`progress` line; one `EncodeProgress` SHALL be reported per block, carrying the block's `frame`,
`fps`, output time in seconds (`out_time_us` or `out_time_ms`, microseconds divided by a
million), `speed` as a plain number with its `x` stripped (a non-numeric speed such as `N/A`
reads as none), and `finished` true exactly when the block ends `progress=end`. Incoming bytes
SHALL be split into lines on both `\n` and `\r` across read boundaries, holding a partial last
line until it completes; the final partial line is delivered when the stream closes.

#### Scenario: one block becomes one report
- **WHEN** the lines `frame=10`, `fps=25.0`, `out_time_us=400000`, `speed=1.5x`, `progress=continue` arrive
- **THEN** one report comes back: frame 10, 25 fps, 0.4 seconds of output, speed 1.5, not finished

#### Scenario: the end of the encode
- **WHEN** a block ends `progress=end`
- **THEN** the report has `finished` true

Pinned by: `Tests/EncoderTests/ArgumentsTests.swift` (`progressBlocksBecomeReports`, `linesAreSplitAcrossChunks`), `Tests/EncoderTests/IntegrationTests.swift` (`aSampleIsEncodedToTheLayoutTheRecipePromised`).

### Requirement: A failing tool carries the tail of what it said

A tool exiting with a non-zero status SHALL throw `ToolError.failed` carrying the tool's name,
its exit status and the tail of what it wrote to standard error — the last 8 KB, kept so a long
run's failure message is its relevant end. Cancelling the awaiting task SHALL terminate the
child process, so a cancelled encode does not run on.

#### Scenario: ffmpeg fails on a missing input
- **WHEN** ffmpeg is run against `/nonexistent/file.mkv`
- **THEN** it throws a `ToolError.failed` naming ffmpeg and its exit status, with ffmpeg's own error in the message

Pinned by: `Tests/EncoderTests/IntegrationTests.swift` (`aFailureCarriesWhatFFmpegSaid`). Task-cancellation termination is pinned by nothing yet.

### Requirement: ffprobe's JSON is reduced to a probed source

`ffprobe` SHALL be run as `-v error -print_format json -show_format -show_streams <file>` and its
output reduced to a `ProbedSource` by a pure function, so the reduction is testable on a captured
document with no `ffprobe` present. `codec_type` maps to the stream kinds video, audio, subtitle,
data and attachment, anything else to `other`; `disposition` entries with a non-zero value become
the stream's set of dispositions; `language` and `title` come from the stream's tags in either
letter-case; the frame rate comes from `avg_frame_rate` then `r_frame_rate`, parsing
`30000/1001` as 29.97 and `0/0` as no rate at all; the duration comes from the format object.
Output that does not decode SHALL throw `ToolError.unreadableOutput` naming `ffprobe`.

#### Scenario: the document is reduced to what facts need
- **WHEN** a probe document holds an h264 progressive stream tagged `language=eng`, a DTS-HD MA track, an AC-3 track tagged `LANGUAGE=eng` and `TITLE=Commentary` with disposition `comment=1`, a forced PGS subtitle and a ttf attachment
- **THEN** the probed source has five streams with the right kinds and dispositions, reads the upper-case tags, keeps the `DTS-HD MA` profile, and takes the duration 1500.32 from the format

#### Scenario: 0/0 is no rate, not a rate of zero
- **WHEN** a stream reports `avg_frame_rate` `0/0`
- **THEN** its frame rate is nil

#### Scenario: something that is not ffprobe's output
- **WHEN** the output is not JSON
- **THEN** `ToolError.unreadableOutput` is thrown

Pinned by: `Tests/EncoderTests/ProbeParsingTests.swift` (`theDocumentIsReducedToWhatFactsNeed`, `aFractionalRateIsAFraction`, `somethingThatIsNotFFprobesOutputIsRefused`).

### Requirement: The encoded output is verified against the recipe's layout

The finished output SHALL be probed and compared against the recipe's layout: the same video,
audio and subtitle streams in the same order (attachments and data streams are ignored), and,
where the expected codec is known, the same codec — the source's own for a copy, the encoder's
output name from a fixed table for an encode (`libx264` and the other h264 encoders read back as
`h264`, the HEVC encoders as `hevc`, `aac` as `aac`, `flac` as `flac`, `dca` as `dts`, and so
on). An encoder the table does not know is not checked — not checked, never counted wrong. Every
disagreement SHALL be a `LayoutMismatch` reading `stream <position>: expected <kind or kind and
codec>, found <what the probe saw or nothing>`, a stream the layout did not expect is a mismatch
that expects nothing, and the comparison SHALL NOT silently pass any extra or missing stream.
Because the sidecar's `<track>` indices are computed from the layout, any mismatch fails the
encode; a file that fails is never treated as the promised presentation.

#### Scenario: the output matches what the recipe promised
- **WHEN** the probed output is h264, flac, aac, PGS in layout order, plus a font attachment
- **THEN** verification finds no mismatches

#### Scenario: the output is renumbered, wrong and long
- **WHEN** the two audio streams come back swapped as aac then flac and an extra AC-3 stream follows
- **THEN** the mismatches are "stream 1: expected audio flac, found audio aac", "stream 2: expected audio aac, found audio flac" and "stream 4: expected nothing, found audio ac3"

#### Scenario: the output is short and the wrong codec
- **WHEN** the probe returns a single hevc video stream
- **THEN** the mismatches are "stream 0: expected video h264, found video hevc" and "found nothing" for each of the three streams that follow

Pinned by: `Tests/EncoderTests/ArgumentsTests.swift` (`theLayoutIsVerifiedAgainstAProbe`), `Tests/EncoderTests/IntegrationTests.swift` (`aSampleIsEncodedToTheLayoutTheRecipePromised`).

### Requirement: The tool's build and encoders are readable

The driver's `version()` SHALL return the first line of `ffmpeg -version` — what a node reports
as the build it runs — and `encoders()` SHALL return the encoder names listed by
`ffmpeg -encoders`, parsed from the lines after the table's header.

#### Scenario: the encoders a node can use
- **WHEN** `encoders()` runs against a real ffmpeg
- **THEN** the set contains at least `flac` and `aac`

Pinned by: `Tests/EncoderTests/IntegrationTests.swift` (`theEncodersAreListed`). `version()` is pinned by nothing yet.

### Requirement: silo-ctl encode resolves, shows, runs and verifies one file

`silo-ctl encode` SHALL encode one file from one ruleset with no server: it takes `--ruleset
<path>` (required), the assignment as the command line knows it — `--kind`, `--profile`,
`--format dvd|bluray|uhd`, optional `--makemkv <json file>` of `MakeMKVFacts`, and repeatable
`--commentary`, `--descriptive` and `--music` stream numbers counted from one among audio, of
which commentary and music also map the features `commentary` and `music` — then the positional
input and output paths, the output required unless `--dry-run` is given. It SHALL probe the
input, derive the facts, resolve the recipe and print the decision before anything is encoded:
the ruleset's name, one line per decision as `<kind> <index>  <facts> -> copy|drop|encode <codec>
(<rule>)` with the output placement `=> <kind> <n>` for kept streams, then the feature map as
`track <feature> -> audio <n>` lines with the track indices renumbered to the output — or, with
`--json`, the recipe as pretty-printed JSON. Fact hints SHALL print as `hint:` lines and the
recipe's warnings as `warning:` lines. A stream no rule decides SHALL print the hints and
`error: no rule decides …` to standard error and exit failing. Then — unless `--dry-run` — it
SHALL run the encode with a progress line on standard error, re-probe the output, verify it
against the layout and print `layout verified: <n> streams as the recipe promised`, or print each
`layout mismatch:` to standard error and exit failing.

#### Scenario: dry run shows the recipe and encodes nothing
- **WHEN** `silo-ctl encode --ruleset Examples/household.xml --kind featurette --dry-run in.mkv` runs
- **THEN** the decision table prints, and no output path is required and no encode happens

#### Scenario: the output is required to encode
- **WHEN** the command runs without `--dry-run` and without an output path
- **THEN** it is refused with "an output path is required unless --dry-run is given"

#### Scenario: the layout does not come back as promised
- **WHEN** verification finds a mismatch after the encode
- **THEN** each mismatch prints as a `layout mismatch:` line and the command exits failing

Pinned by: nothing yet.
