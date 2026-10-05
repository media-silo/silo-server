<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## REMOVED Requirements

### Requirement: Losslessness and role are each derived in one place
**Reason**: Role and core-ness were derived from MakeMKV's stream flags and scan, which the silo no
longer receives; they are now derived from the input spec's marks and `coreOf`.
**Migration**: The requirement added below, "Losslessness, role and core-ness are each derived in
one place", states the derivation from the input spec.

### Requirement: Facts are merged once from the probe, the scan and the assignment
**Reason**: The silo no longer receives a probe or a MakeMKV scan; a producer describes each source
in an input spec, and reconciling a scan with a probe is that producer's work.
**Migration**: Facts are derived from a binding, its sources' input specs and an output, as the
requirement added below states.

## MODIFIED Requirements

### Requirement: The output layout maps source streams to output streams

The recipe's layout SHALL list the streams the output will have — video first, then the surviving
audio streams, then the surviving subtitles, each in source order — with every entry pointing back
at its source stream by per-kind index and absolute index, and numbered with an `outputIndex`
from one among output streams of the kind and an `outputAbsoluteIndex` from zero across the whole
output, `ffmpeg`'s own count. The layout is computed before the encode, so the new presentation's
`<track>` indices are known without opening the output: `tracks(for:)` SHALL renumber the
binding's feature map through it, and a mapping whose stream the recipe drops SHALL be left
out.

#### Scenario: a dropped stream renumbers what follows
- **WHEN** the household ruleset gains rules dropping lossless audio and forced subtitles and resolves the episode, whose commentary is source audio 2
- **THEN** the layout is video, audio, audio, subtitle; source audio 2 becomes output audio 1 and source audio 3 becomes output audio 2; the feature mapped to audio 2 renumbers to `audio="1"`; and the features mapped to the dropped streams are left out of the renumbered map

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`aDroppedStreamRenumbersWhatFollowsAndWarnsAboutAMappedOne`).

### Requirement: Resolution is a pure function of the facts and the ruleset

`RecipeResolver.resolve` SHALL take every input as a value — the file's facts, the ruleset, the
binding's feature map — and return the recipe or throw `ResolutionError`, with no file read
and no `ffprobe` or `ffmpeg` run. The two derived facts, the closed vocabulary and the file
reader exist so that the resolver never needs to ask anything else.

#### Scenario: the proposal's rules resolve against a literal DVD featurette
- **WHEN** the household ruleset resolves literal facts for a 352x288 interlaced MPEG-2 featurette with one AC-3 stereo track
- **THEN** the video is encoded by `small-extras` as libx264, preset slow, CRF 22, yuv420p, deinterlaced automatically, and the audio falls to the catch-all copy — with no tool and no file involved

Pinned by: `Tests/SiloKitTests/ResolverTests.swift` (`aSmallExtraIsReencoded`).
