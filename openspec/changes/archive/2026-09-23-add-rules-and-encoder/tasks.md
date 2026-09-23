<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Tasks

**Retrospective archive — every task was completed in pull request #1 (merged 2026-09-23).**

## 1. SiloKit: facts, the ruleset file, the resolver

- [x] 1.1 Model the closed facts vocabulary (`FactKey`, `SourceFacts`, `ProbedSource`,
  `MakeMKVFacts`) and derive `lossless` and `role` in one place, reporting disagreements as hints
- [x] 1.2 Read and write the ruleset XML document: scoped rules, `<when>` conditions with the
  seven operators, `<copy/>`/`<drop/>`/`<encode>` actions, the `<extraction>` policy and
  `<output>`, with parse errors for unknown facts, wrong scopes and unknown elements
- [x] 1.3 Implement the resolver and the recipe: first matching rule decides, undecided stream is
  an error, one decision per stream naming its rule, the output layout renumbering the feature
  map, mapped-but-dropped as warnings
- [x] 1.4 Test facts, the ruleset file and the resolver on literal values (`Tests/SiloKitTests`)

## 2. Encoder: ffprobe and ffmpeg as processes

- [x] 2.1 Run the tools as processes: locate by environment, `PATH` and fallbacks; stream
  standard output a line at a time; keep the stderr tail for failures; kill on cancellation
- [x] 2.2 Reduce ffprobe's JSON to `ProbedSource`, compile a recipe to one ffmpeg argument list,
  parse `-progress pipe:1` blocks into reports, and verify the output's layout against the recipe
- [x] 2.3 Test arguments, probe parsing, progress and layout checks on values, plus one real
  encode when ffmpeg is installed (`Tests/EncoderTests`)

## 3. silo-ctl encode and the example ruleset

- [x] 3.1 Add the `encode` command: read the ruleset file, probe, take the assignment from the
  command line, resolve, print the decision renumbered to the output, encode with progress, and
  verify the layout (`--dry-run`, `--json`)
- [x] 3.2 Ship `Examples/household.xml`, the proposal's ruleset as a file, pinned by a test
  against the in-code fixture
