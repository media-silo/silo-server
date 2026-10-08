<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A binding's own rules are the nearest layer
A binding's rules, versioned as a container's are and read from their version files exactly as a
container's are, SHALL be the nearest layer of the stack of any entry made from the binding, ahead of
every container's. A binding with no rules SHALL contribute no layer. A rule in a binding's rules
SHALL be written as any rule is, and is what a person's decision about that one entry is.

#### Scenario: a binding's rule speaks first
- **WHEN** the item's container has a rule encoding lossless audio as FLAC, and the binding's rules
  hold `<audio><when fact="audio.index" is="1"/><copy/></audio>`
- **THEN** the entry's first audio stream is copied by the binding's rule, and its other lossless
  audio streams are encoded by the container's

Pinned by: nothing yet.
