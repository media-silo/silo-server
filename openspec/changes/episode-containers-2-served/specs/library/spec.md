<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A container's first date agrees with its year
A container with both a `year` and a `premiered` whose year is another SHALL be a warning-severity
finding (`premiered <date> is not in <year>`): the two are authored separately, as a series' year may
be the year it began and its first date the day, and one that disagrees is more likely a typo than a
choice.

#### Scenario: a film dated in another year
- **WHEN** a film's sidecar has the year 1979 and the first date 1978-12-01
- **THEN** the validator warns `premiered 1978-12-01 is not in 1979`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`aFirstDateInAnotherYearIsAWarning`).
