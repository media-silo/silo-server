<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A special placed among a season's episodes is an episode container
A special placed in a season's run SHALL be an episode container among its siblings, drafted as an
episode is, and one placed as a version of an episode SHALL be an alternative of that episode's
container, in a sequence of the container's own.

#### Scenario: a special as a version of one episode
- **WHEN** a special is placed at an episode's stop as a version of the episode, and the stop confirmed
- **THEN** storing the walk adds to the episode's container a sequence holding the special and an
  alternative naming it, and the season's sequences are unchanged

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aSpecialAsAVersionIsAnAlternativeOfTheEpisode`).
