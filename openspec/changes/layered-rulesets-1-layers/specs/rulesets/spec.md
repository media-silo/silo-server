<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A container's rules are a layer written in the ruleset language
A container's `<rules>` element, carried in its sidecar as [library](../library/spec.md)
describes, SHALL hold rule elements — `<video>`, `<audio>` and `<subtitle>` — read exactly as the
rules of a ruleset are read, and nothing else: an `<extraction>`, `<output>` or any other element
in it SHALL be refused as not an element of a container's rules. A container's rules are refused
whole, as a ruleset is, and their unnamed rules are named `#n` by their position among the
element's rules.

#### Scenario: a container's rules read as a ruleset's
- **WHEN** a container's `<rules>` holds `<video id="keep"><when fact="kind" ne="episode"/><copy/></video>`
- **THEN** it reads as one video rule named `keep`

#### Scenario: no outputs in a container's rules
- **WHEN** a container's `<rules>` holds an `<output container="mp4"/>` element
- **THEN** the rules are refused, saying `<output>` is not an element of a container's rules

Pinned by: nothing yet.

### Requirement: An entry's rules are a stack of layers, nearest first
The rules that decide an entry SHALL be a stack of layers: the `<rules>` of the container holding
the item, then those of each of its ancestors in turn, nearest first, and last the ruleset applied,
at the version resolved. A container with no sidecar, or whose sidecar has no `<rules>`,
contributes no layer. For each stream, the rules of the stream's scope SHALL be tried layer by
layer, and within a layer in document order; the first that matches decides, and no later rule in
any layer is consulted. Every output SHALL be resolved through the same stack, with `profile` set
to its profile. The outputs and the extraction policy SHALL be the applied ruleset's alone.

#### Scenario: a container's rule speaks first
- **WHEN** the ruleset applied encodes every lossless audio stream as FLAC, the item's container has
  one rule copying lossless audio, and the entry has one lossless audio stream and one lossy one
- **THEN** the lossless stream is copied by the container's rule, and the lossy stream falls
  through to the ruleset's rules

#### Scenario: the nearer container wins
- **WHEN** a serial's rules copy commentaries, the series holding it has rules dropping them, and an
  episode of the serial has a commentary
- **THEN** the commentary is copied by the serial's rule

#### Scenario: a condition-less container rule ends its scope
- **WHEN** a container's rules hold `<audio><copy/></audio>`
- **THEN** every audio stream of every item below it is copied, and no audio rule of the ruleset
  applied decides any of them

Pinned by: nothing yet.
