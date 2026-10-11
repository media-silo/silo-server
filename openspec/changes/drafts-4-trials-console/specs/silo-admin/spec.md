<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A branch's version is tried on chosen bindings, and each trial compared with what is placed
From a version on a branch, SiloAdmin SHALL let the operator choose bindings to try it on, offering
first the bindings of the presentations its impact on the standard lists, and SHALL apply the branch at
that version to each and make a trial job of each recipe the application makes. It SHALL show each
trial job's progress, and for a tried trial, beside the presentation its binding placed, each stream's
decision in the placed recipe and in the trial's, and both files to play. It SHALL place nothing.

#### Scenario: three trials of a lowered bitrate
- **WHEN** the operator tries a branch's version that lowers the commentary bitrate on three bindings
  its impact lists, and the trials are encoded
- **THEN** each trial shows its commentary at the new bitrate beside the placed presentation's at the
  old, and nothing has been placed

Pinned by: nothing yet.
