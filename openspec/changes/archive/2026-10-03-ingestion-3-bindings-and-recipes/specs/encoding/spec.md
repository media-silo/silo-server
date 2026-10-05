<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

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
