<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A container's artwork is found beside its sidecar by name
A container's artwork SHALL be the files in its folder, beside `container.smd`, named
`<kind>.jpg` or `<kind>.png` for the kinds `poster`, `fanart`, `banner`, `logo` and `thumb`.
The sidecar SHALL list none of it, and a placement or an edit SHALL leave it as it stands. A kind
held as both a `.jpg` and a `.png` beside one sidecar SHALL be a warning the walk reports on
the sidecar (`<kind> is both <kind>.jpg and <kind>.png`), and the `.jpg` is the one that counts.

#### Scenario: a poster in two formats
- **WHEN** a container's folder holds both `poster.jpg` and `poster.png`
- **THEN** the walk warns on its sidecar that `poster` is both, and the container's poster is
  `poster.jpg`

Pinned by: nothing yet.
