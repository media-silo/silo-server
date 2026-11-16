<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: silo-node is the node's side of it all
`silo-node` SHALL be the executable a machine other than the silo's runs, with the options
`--silo`, `--name` (defaulting to the machine's host name), `--serve-port`
(defaulting to 18600), `--advertised-host` (defaulting to the machine's host name) and `--poll`
(the seconds between asking for work, defaulting to 5). On start it SHALL require its `ffmpeg`
and `ffprobe` — a node without them has nothing to offer — and SHALL register its name, its
platform (`macOS`, `Linux` or `other`), the encoders its `ffmpeg` reports sorted, the first line
of `ffmpeg -version`, and the machine's active core count. Its registration and each approval poll
lost in transport SHALL be sent again for as long as it takes, as a request lost in transport is, so
a node started while the silo is down or restarting waits for it rather than exiting. While
unapproved it SHALL poll every five seconds and log once `waiting for approval: on the silo, run  silo-ctl nodes approve <id>`.
Once it holds its token it SHALL serve what it makes on the serve port under the advertised
host — each output published at `<job>/output` with itself as holder for the silo to fetch at
placement — and SHALL run the worker's loop with the token, the same loop the embedded node
runs, so there is one code path to test. The file server and the worker SHALL run as one service
group: a server that fails while serving SHALL end the worker too and the node with the server's
error, and SIGTERM or SIGINT SHALL shut both down gracefully, the worker first, its job in flight
cancelled as the embedded node's is.

#### Scenario: approval arrives
- **WHEN** `silo-node` runs unapproved and a person approves its id on the silo
- **THEN** within five seconds a poll takes and saves the token, and the run continues with `ready: <n> encoders, serving outputs on port 18600`

#### Scenario: the server cannot serve
- **WHEN** the node's file server fails while the worker is running, as it does when its port is taken
- **THEN** the worker is stopped too and the group ends with the server's error

#### Scenario: the node is told to stop
- **WHEN** the node's service group is shut down gracefully, as SIGTERM or SIGINT does
- **THEN** the worker and then the file server stop, and the group ends without an error

#### Scenario: the silo is down when the node starts
- **WHEN** `silo-node` starts while the silo cannot be reached
- **THEN** it logs that the silo is unreachable, sends its registration again, and registers once the
  silo answers

Pinned by: `Tests/SiloTests/NodeServicesTests.swift` (`aServerThatFailsEndsTheWorkerToo`,
`aGracefulShutdownStopsTheWorkerAndTheServer`), for the two services in one group as `silo-node` runs
them. The rest, the signals reaching the group, and a registration sent again
are pinned by nothing yet. Sending a request lost in transport again is pinned by
`Tests/SiloTests/BackoffTests.swift` (`aTransportErrorIsSentAgainWaitingLongerEachTime`).
