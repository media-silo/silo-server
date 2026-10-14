<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Facts are derived once from a binding, its sources and an output
`SourceFacts` SHALL be derived, in one place, from a binding, the input spec of its first segment's
source, and one output of its ruleset. `kind` SHALL be the item's, from the lineage; `extra` SHALL be true when the lineage's last
container holds the item in its extras and false when it holds it in a sequence; `profile` SHALL
be the output's; `format` SHALL be the first segment's `medium`; `duration` SHALL be the joined
spans' length; and an audio stream a feature is mapped to SHALL take its role from that feature —
`commentary` for a commentary, `isolatedMusic` for isolated music, `other` otherwise. The first video
stream SHALL be described and further video streams reported as a hint. Each stream's codec, size,
bit depth, channels and title SHALL be the spec's; an audio or subtitle stream's `language`,
`script` and `region` SHALL be its language tag's primary language, script and region subtags, each
absent when the tag has none or the stream has no tag; `video.frameRate` SHALL be the spec's
fraction as a number, its numerator divided by its denominator; `video.interlaced` SHALL be the
spec's `interlaced`, false when absent; `video.hdr` SHALL be `hdr10` for a `transfer` of
`smpte2084`, `hlg` for `arib-std-b67`, and absent otherwise; `subtitle.forced` SHALL be whether the
stream is marked `forced`. Streams of kind `other` SHALL be neither described nor decided. The
specs' notes SHALL join the hints the derivation raises. Audio and subtitle streams SHALL be numbered
from one among the streams of their kind — the way a player's menu counts and the way the sidecar's
`<track audio="n">` counts — while each keeps the spec's `index` as its `absoluteIndex`.

#### Scenario: HDR from the transfer characteristic
- **WHEN** a source's video stream has `transfer` `smpte2084`, and another's has `bt709`
- **THEN** the first's `video.hdr` is `hdr10` and the second's is absent

#### Scenario: a language tag split into its parts
- **WHEN** one audio stream's language is `es-419` and a subtitle stream's is `zh-Hant`
- **THEN** the audio's `language` is `es` and its `region` `419`, with no `script`; the subtitle's
  `language` is `zh` and its `script` `Hant`, with no `region`

#### Scenario: a fractional frame rate
- **WHEN** a source's video stream has `frameRate` `24000/1001`
- **THEN** the `video.frameRate` fact is 24000 divided by 1001, and a rule testing
  `<when fact="video.frameRate" lt="24"/>` holds for it

#### Scenario: a title that says commentary is a hint, not a role
- **WHEN** an audio stream at index 3 is titled "Commentary with the director" and nothing marks it
- **THEN** its role stays `main` and a hint on stream 3 reads: titled "Commentary with the director" but nothing marks it a commentary; assign it to a feature if it is one

#### Scenario: an extra and an episode
- **WHEN** one binding's item is held in its container's extras and another's in a sequence
- **THEN** the first's facts have `extra` true and the second's `extra` false, and each recipe records
  it

#### Scenario: an episode's duration
- **WHEN** a binding spans chapter 2 of a source whose chapters start at 0, 1497.6 and 2995.2 seconds
- **THEN** the `duration` fact is 1497.6

Pinned by: `Tests/SiloKitTests/BindingTests.swift` (`factsAreDerivedFromWhatWasObserved`, `anEpisodeOutOfAPlayAllTitleIsItsChapterSpan`),
`Tests/SiloTests/BindingRulesTests.swift` (`anExtraIsWhereItsContainerFilesItWhateverItsKind`).
