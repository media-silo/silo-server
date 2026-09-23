<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Add the rules engine, the encoder, and silo-ctl encode

**Retrospective archive — merged 2026-09-23 as pull request #1.** This change predates the
corpus; its documents were reconstructed from the merge afterwards.

## Why

Between the folder of ripped MKVs the roadmap's first phase ends with and something a person sits
down and watches, the first unnamed job is deciding how each file is encoded. A ripped Blu-ray
episode holds maybe a lossless master mix, a stereo mix, a commentary and three subtitle streams,
and the right answer for each is not the same, nor the same for a featurette at standard
definition as for the feature. Made by hand, per file, the decision is made badly on the third
disc and inconsistently by the tenth. The proposal's answer: facts are discovered, rules are
written, and a ruleset resolved against a file's facts yields a recipe that is followed exactly
and can be read afterwards. The proposal's roadmap also says how this lands first: the rules,
pure and testable, with an `ffmpeg` driver and a command that encodes one file from one ruleset,
are useful before a server exists.

## What Changes

- `SiloKit` gains the facts vocabulary: `SourceFacts` for what a file is and holds, merged once
  from `ffprobe`'s probe, MakeMKV's scan and the assignment, with the two derived facts —
  `lossless` as a function of codec and profile, `role` ranked assignment, then disc flags, then
  dispositions — each derived in exactly one place, and disagreements reported as hints rather
  than chosen between.
- The ruleset XML file: a named, versioned document of ordered rules in three scopes, conditions
  as `<when fact …>` with the seven operators `is`/`ne`/`in`/`lt`/`le`/`gt`/`ge`, actions
  `<copy/>`, `<drop/>` and `<encode …>`, the `<extraction>` policy as a sibling element, and
  `<output>` naming the container. An unknown fact, a fact in the wrong scope, or an unknown
  element is a parse error, not a rule that never matches.
- The resolver and the recipe: the first matching rule in each scope decides each stream; a
  stream no rule decides is an error naming the stream and its facts; the recipe records one
  decision per stream, each naming its rule, plus the output layout that renumbers the
  assignment's feature map to the output; a feature mapped to a dropped stream is a warning. The
  resolver is pure — no file, no tools.
- `Encoder`: `ffprobe` and `ffmpeg` as processes located by `FFPROBE_PATH`/`FFMPEG_PATH`, `PATH`
  and the package-manager fallbacks; ffprobe's JSON reduced to a `ProbedSource` by a pure
  function; the recipe compiled to one argument list with per-output-stream options; progress
  parsed from `-progress pipe:1` blocks a report at a time; and the encoded output probed and
  checked against the recipe's layout, any mismatch failing.
- `silo-ctl encode`: a ruleset file plus the kind, profile, format, MakeMKV scan and
  commentary/descriptive/music stream numbers as the assignment; it prints the decision with the
  feature map renumbered to the output, encodes, and verifies the output's layout — with
  `--dry-run` and `--json` beside.
- `Examples/household.xml`: the proposal's three rules and three catch-alls as a file, pinned by
  a test to the fixture the resolver tests run against.

## Impact

- Affected specs: rules, encoding.
- Affected code: `Sources/SiloKit` (facts, rules, ruleset file, recipe, resolver),
  `Sources/Encoder` (process running, ffprobe, ffmpeg, arguments, layout check),
  `Sources/silo-ctl` (the `encode` command), `Examples/household.xml`; tests in
  `Tests/SiloKitTests` and `Tests/EncoderTests`, including one integration test that runs the
  real tools where they are installed.
