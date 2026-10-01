<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## RENAMED Requirements

- FROM: `### Requirement: SILO_EMBEDDED_NODE=true runs the loop inside the silo`
- TO: `### Requirement: The embedded node setting runs the loop inside the silo`

## MODIFIED Requirements

### Requirement: The embedded node setting runs the loop inside the silo
When the embedded node setting is on — `embeddedNode` in `settings.json`, false by default, per
[configuration](../configuration/spec.md) — the silo SHALL run a worker inside itself as a
background service: node id `embedded`, work folder `<state directory>/work`, asking the job service
directly rather than over HTTP, its outputs published as `file://` references — holder `embedded`,
the local path carried, an empty secret — which placement moves rather than fetches. The service
SHALL follow the setting while the silo runs: turned on, it SHALL start the loop; turned off, it
SHALL stop claiming and let a job in flight run to completion. While the setting is off the service
SHALL stay up and do nothing, so the group it runs in is not ended; when the encode tools cannot be
started it SHALL log the lack and idle rather than stop the silo.

#### Scenario: one machine is the whole pipeline
- **WHEN** the silo runs with the embedded node on and a job becomes pending
- **THEN** the embedded loop claims it, encodes it, and completes it with an output on the silo's
  own filesystem

#### Scenario: turned on while running
- **WHEN** the embedded node is off, a job is pending, and the operator turns the setting on
- **THEN** the embedded loop starts and claims the job, without a restart

Pinned by: `Tests/SiloTests/JobTests.swift` (`theEmbeddedNodeEncodesAndTheSiloPlaces`). The
setting-off, tool-less and live-toggle arms are pinned by nothing yet.
