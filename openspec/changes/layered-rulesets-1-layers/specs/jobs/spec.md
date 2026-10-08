<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Placement fetches the output from its holder and files it
`POST /v1/jobs/{id}/place` SHALL take only an `encoded` job with its output present; anything else
is 409, and a binding naming a library the silo no longer has is 404. The job SHALL become `placing`
while the silo works. The output SHALL be staged at `<library>/.silo/incoming/<job id>.<ext>`: moved
across when the output is a file URL — the embedded node's output is on this filesystem already —
and fetched over HTTP with the file's secret in `x-silo-secret` when it is remote, a non-200 answer
becoming 502 (`the node answered <status> for the output`). The presentation SHALL be built from the
binding of the job's recipe — its item, alternative and chapter names, its feature map renumbered by
the recipe's layout — in the profile of the recipe's output, with its provenance: a `<source>` naming
the binding and holding one `<segment>` per segment in order, each its source's natural key when it
has one and its chapter span when it has one, and a `<transform>` holding the recipe's stack, its
ruleset and version and a `<layer>` for each layer above it with its version and digest; the placement
computed and, when it would not apply, refused whole with its reasons as 409; otherwise applied and
the library re-scanned, so the index learns of the new presentation. The job SHALL then be `placed`
with a summary of the destination relative to the library root, the presentation's id, and the
writes made. Any failure along the way SHALL return the job to `encoded` with the failure recorded.

#### Scenario: an encoded job is placed
- **WHEN** the operator places an encoded job whose binding is part three of the serial *Pyramids of
  Mars*, in the series *Doctor Who (1963)* in library `main`, made by the unqualified output
- **THEN** the job is `placed` at `Doctor Who (1963)/Pyramids of Mars/Part Three.mkv`, the index
  answers its presentation id (and the media route serves it by range), the serial's sidecar names
  the binding and the recipe's ruleset version on the presentation, and a second place is 409

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromADraftToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`), `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`, for the `- mobile` naming and the file moved out of the work folder). The presentation's provenance is pinned by nothing yet.
