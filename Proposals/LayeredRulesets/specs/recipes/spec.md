<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A decision names the layer its rule came from
Each decision in a recipe SHALL name, beside its rule, the layer the rule came from: the library's
ruleset as `name@version`, or a container's rules by the container's id. The rule SHALL be named
within its layer — its `id`, or `#n` for its position among that layer's rules.

#### Scenario: two layers decide one file
- **WHEN** a file's video is decided by the unnamed first rule of container `00000000000000a3`'s
  rules and its audio by the rule `lossless-main` of `household@7`
- **THEN** the video's decision names rule `#1` of layer `00000000000000a3`, and the audio's names
  rule `lossless-main` of layer `household@7`

Pinned by: nothing yet.
