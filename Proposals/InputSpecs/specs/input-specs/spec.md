<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: An input spec describes a mezzanine's streams in the silo's vocabulary
An input spec SHALL be a JSON object describing one input mezzanine: an optional `label`, free text
a person will recognise; an optional `medium`, one of `dvd`, `bluray` and `uhd`, for a mezzanine
that came from one; an optional `duration` in seconds; `streams`; and optional `notes`. Each stream
SHALL carry `index`, its position among all the mezzanine's streams from zero, as `ffmpeg`
addresses it; `kind`, one of `video`, `audio`, `subtitle` and `other`; and `codec`. A stream MAY
carry `profile`; for video, `width` and `height`, both required, and `frameRate`, `interlaced`,
`transfer` and `bitDepth`; for audio, `channels`, required, and `layout`; for any stream,
`language`, `title`, `marks` and, for audio, `coreOf`. Codec, profile, transfer and layout names
SHALL be `ffmpeg`'s; a language SHALL be an ISO 639-2 code. `marks` SHALL be drawn from `default`,
`forced`, `commentary`, `descriptive` and `hearingImpaired`. `coreOf` SHALL name the `index` of the
lossless audio stream a lossy core was extracted from. A note SHALL carry `text` and MAY name a
stream by its `index`; notes are shown to a person and are never facts. An input spec says what
was observed of the mezzanine and SHALL NOT carry a fact a rule tests that the silo derives:
losslessness, role, HDR kind or core-ness.

#### Scenario: a disc title described
- **WHEN** a producer describes a mezzanine with an interlaced MPEG-2 video stream, a two-channel
  English AC-3 main mix marked `default`, an English AC-3 track marked `commentary`, and a forced
  English DVD subtitle stream
- **THEN** the input spec holds four streams, indexed 0 to 3, with those codecs, marks and
  languages, and no role or losslessness for any of them

Pinned by: nothing yet.

### Requirement: An input spec that is not well formed is refused, naming what is wrong
The silo SHALL refuse an input spec, naming the fault, when two streams share an `index`; a `kind`
or a mark is not in the vocabulary; a `medium` is not one of the three; a stream lacks `index`,
`kind` or `codec`; a video stream lacks `width` or `height`; an audio stream lacks `channels`; or a
`coreOf` names no audio stream of the spec, or names its own stream. A spec the silo refuses SHALL
change nothing.

#### Scenario: a repeated index
- **WHEN** an input spec has two streams at index 1
- **THEN** it is refused, naming index 1

#### Scenario: a mark the vocabulary does not have
- **WHEN** a stream is marked `karaoke`
- **THEN** it is refused, naming the mark `karaoke`

#### Scenario: a core of nothing
- **WHEN** an audio stream's `coreOf` names index 9, and the spec has no stream 9
- **THEN** it is refused, naming the stream and index 9

Pinned by: nothing yet.

### Requirement: The plain-file producer describes a file from its probe
The silo's plain-file producer SHALL write an input spec from what `ffprobe` reports of a file,
with no other source: each probed stream's index, kind, codec, profile, size, frame rate, bit
depth, channels, layout, language and title as reported; `interlaced` true when `field_order` is
anything but `progressive` or absent; `transfer` from `color_transfer`; and marks from the
dispositions that are set — `default`, `forced` and `hearing_impaired` as `default`, `forced` and
`hearingImpaired`, `comment` as `commentary`, and `visual_impaired` or `descriptions` as
`descriptive`. It SHALL set no `medium`, no `coreOf` and no notes, since a plain file tells it
neither. A probed stream of kind data, attachment or other SHALL be described with kind `other`.

#### Scenario: a probed file described
- **WHEN** a probe reports a progressive h264 stream, an AC-3 stream with disposition `comment`
  tagged `LANGUAGE=eng`, and a forced PGS subtitle
- **THEN** the input spec has a video stream not interlaced, an audio stream marked `commentary`
  with language `eng`, and a subtitle stream marked `forced`, and no medium

Pinned by: nothing yet.
