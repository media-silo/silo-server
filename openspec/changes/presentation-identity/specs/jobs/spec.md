<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A job's placed presentation id is carried over to the new form once
After the first walk of a library under ids formed from what a presentation is, the server SHALL
replace, in each job record of that library whose placement summary names a presentation id the index
does not hold, that id with the id of the presentation the index holds at the summary's destination,
and SHALL write the record again. A job whose destination the index does not hold SHALL keep the id
it has. A record whose id the index holds SHALL NOT be written.

#### Scenario: a job placed before the change
- **WHEN** a job's placement summary names its presentation by the hash of its library and path, and the server starts under the new ids
- **THEN** after the first walk the record names the presentation's new id, the presentation is not reported as placed without a job, and the out-of-date report describes it

#### Scenario: a job whose file has gone
- **WHEN** a job's placement summary names a destination the index does not hold
- **THEN** the record keeps the id it has

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobsPlacedPresentationIsCarriedOverOnce`).
