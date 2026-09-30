<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## REMOVED Requirements

### Requirement: Losslessness and role are each derived in one place
**Reason**: Role and core-ness were derived from MakeMKV's stream flags and scan, which the silo no
longer receives; they are now derived from the input spec's marks and `coreOf`.
**Migration**: The requirement added below, "Losslessness, role and core-ness are each derived in
one place", states the derivation from the input spec.

### Requirement: Facts are merged once from the probe, the scan and the assignment
**Reason**: The silo no longer receives a probe or a MakeMKV scan; a producer describes the
mezzanine in an input spec, and reconciling a scan with a probe is that producer's work.
**Migration**: Facts are derived from the input spec and the assignment, as the requirement added
below states.

## ADDED Requirements

### Requirement: Losslessness, role and core-ness are each derived in one place

`AudioFacts.isLossless` SHALL be a function of codec and profile only, so that the producer, the
resolver at assignment and the node at encode time agree: TrueHD, MLP, FLAC, ALAC, WavPack, TTA,
APE and any `pcm_` codec are lossless, DTS is lossless only when its profile is DTS-HD Master Audio
(the DTS-HD High Resolution profile is not), and anything else is not.

`AudioRole` SHALL be derived from the sources in order of authority: the assignment's feature map
first, then the stream's marks in the input spec — `commentary` is commentary, and failing that
`descriptive` is descriptive. When neither speaks the role is `main`. A stream title that merely
says "commentary" SHALL NOT set the role; it is reported as a hint instead. The `core` fact — the
lossy core inside a lossless track, the same audio again, smaller and worse — SHALL be true exactly
for a stream the input spec gives a `coreOf`.

#### Scenario: dts is lossless only as Master Audio
- **WHEN** `isLossless` is called for `("dts", "DTS-HD MA")`, `("dts", "DTS-HD HRA")`, `("pcm_s24le", nil)` and `("ac3", nil)`
- **THEN** the answers are true, false, true and false

#### Scenario: the assignment outranks the marks
- **WHEN** the assignment maps a stream to isolated music while the input spec marks it `commentary`
- **THEN** the role is `isolatedMusic`

#### Scenario: nothing speaks
- **WHEN** no assignment maps the stream and the input spec marks it only `default`
- **THEN** the role is `main`

Pinned by: `Tests/SiloKitTests/FactsTests.swift` (`losslessIsAFunctionOfCodecAndProfile`); the role
from marks is pinned by nothing yet.

### Requirement: Facts are derived once from the input spec and the assignment
`SourceFacts` SHALL be derived, in one place, from a job's input spec and the assignment — the role
of each audio stream the feature map names, `kind`, `profile` and `format`. The first video stream
of the spec SHALL be described and further video streams reported as a hint. Each stream's codec,
size, frame rate, bit depth, channels, language and title SHALL be the spec's; `video.interlaced`
SHALL be the spec's `interlaced`, false when absent; `video.hdr` SHALL be `hdr10` for a `transfer`
of `smpte2084`, `hlg` for `arib-std-b67`, and absent otherwise; `subtitle.forced` SHALL be whether
the stream is marked `forced`; `format` SHALL be the assignment's, else the spec's `medium`.
Streams of kind `other` SHALL be neither described nor decided. The spec's notes SHALL join the
hints the derivation raises. Audio and subtitle streams SHALL be numbered from one among the
streams of their kind — the way a player's menu counts and the way the sidecar's
`<track audio="n">` counts — while each keeps the spec's `index` as its `absoluteIndex`.

#### Scenario: HDR from the transfer characteristic
- **WHEN** an input spec's video stream has `transfer` `smpte2084`, and another's has `bt709`
- **THEN** the first's `video.hdr` is `hdr10` and the second's is absent

#### Scenario: a title that says commentary is a hint, not a role
- **WHEN** an audio stream at index 3 is titled "Commentary with the director" and nothing marks it
- **THEN** its role stays `main` and a hint on stream 3 reads: titled "Commentary with the director" but nothing marks it a commentary; assign it to a feature if it is one

#### Scenario: the medium stands in for the format
- **WHEN** the assignment gives no format and the input spec's `medium` is `bluray`
- **THEN** the `format` fact is `bluray`

Pinned by: nothing yet.

### Requirement: An adjustment replaces a stream's decision and is recorded with what it replaced
Resolution SHALL take optional adjustments, each naming a stream by kind and by its index from one
among streams of its kind, giving an action — `copy`, `drop`, or `encode` with the settings a rule's
`<encode>` carries — and optionally a note. Adjustments SHALL be applied after the ruleset decides
every stream: each replaces the action of its stream's decision, which SHALL keep the rule that
decided it and record the action the rule chose and the note. The layout, the renumbered feature
map, the warnings and the encoders the recipe needs SHALL then follow from the adjusted decisions.
An adjustment naming a stream the recipe has no decision for, or a second adjustment for one
stream, SHALL be refused. A stream no rule decides SHALL still fail resolution, whatever the
adjustments say.

#### Scenario: a stream kept that the rules would encode
- **WHEN** `lossless-main` would encode audio 1 as FLAC, and an adjustment gives audio 1 `copy` with
  the note "keep the Atmos object track"
- **THEN** the recipe copies audio 1, its decision still names `lossless-main` and records that the
  rule chose FLAC and the note, and `flac` leaves the recipe's encoders when no other stream needs it

#### Scenario: a stream dropped renumbers the rest
- **WHEN** an adjustment drops audio 2 of three, and a feature is mapped to audio 2
- **THEN** the layout holds the source's audio 1 and 3 as output audio 1 and 2, and the recipe warns
  that the feature is mapped to a stream this recipe drops

#### Scenario: an adjustment for a stream that is not there
- **WHEN** an adjustment names audio 4 of a mezzanine with three audio streams
- **THEN** resolution is refused, naming audio 4

Pinned by: nothing yet.
