<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A container's first date and credits are served
A `Container` in the read answers SHALL carry the sidecar's `premiered`, as `yyyy-mm-dd`, and its
`cast` and `crew`, each a list of participants with a `name`, a `role` and `externalRefs` in the
order credited. A participant on a feature SHALL carry its `externalRefs` too. A `ContainerSummary`,
wherever one is served, SHALL carry the container's `premiered`, so that a season's answer lists each
of its episodes' titles and dates. An edit and a create SHALL take them in the container's document, as
they take its other fields.

#### Scenario: an episode's date and credits
- **WHEN** an episode container that premiered on 2022-09-21, with a cast member playing a character
  and a director carrying a `wikidata` reference, is read
- **THEN** the 200 answer carries `"premiered":"2022-09-21"`, the cast member with the character, and
  the director in `crew` with that reference

#### Scenario: a season lists its episodes' dates
- **WHEN** a season holding two episode containers, each with a title and a first date, is read
- **THEN** each child's summary carries the episode's title and its `premiered`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aContainersFirstDateAndCreditsAreServed`,
`aSeasonListsItsEpisodesDates`).
