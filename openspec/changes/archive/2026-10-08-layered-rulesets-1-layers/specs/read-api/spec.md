<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The API's types are the sidecar's elements as JSON
One model, per principle 2: the document's schemas SHALL be the sidecar's
elements as JSON, never a separate API vocabulary. A `Container` SHALL carry
the sidecar's `type`, `title`, `displayTitle`, `year`, `typeLabel`, `outline`,
`listed`, `defaultAlternative`, `alternatives`, `features` with their
`participants`, `sequences`, `extrasAnchor`, `extras`, `externalRefs`, and its
child containers as summaries; an `Item` SHALL carry its `optional`, `ref`,
`externalRefs` and `presentations`; a `Presentation` SHALL carry `id`,
`alternative`, `profile`, `displayName`, `file`, `source` — its binding and
segments — `transform` — its ruleset, version and layers — `tracks` and
`chapters`, with a track's `audio` and `subtitle` counting from one among the
streams of that kind. The mapping SHALL run one way only: the API is a
projection of the model, never a place the model is edited.

#### Scenario: a container reads as the sidecar's values
- **WHEN** a client asks `GET /v1/containers/0000000000000003`
- **THEN** the 200 answer carries `"typeLabel":"Story"`,
  `"parent":"0000000000000001"`, and in its presentations
  `"displayName":"mobile"`, `"file":"Part One.mkv"` and a track's `"audio":3`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`).
