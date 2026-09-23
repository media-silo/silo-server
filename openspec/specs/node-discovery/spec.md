<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Node discovery

## Purpose

How a machine that is not the silo becomes a node, and how it stops being one. A node mints and
keeps its own identity and secret, finds the silo by Bonjour or is handed its URL, registers what
its `ffmpeg` can do and is recorded pending and given nothing, waits for a person to approve it,
takes the token the approval minted exactly once, and claims, reports and completes behind that
token until revoking — one state change — cuts it off. This spec covers the node record and its
hashes on the silo, the node routes and their two gates, Bonjour done as child processes of the
platform's own tools, the silo's advertisement of itself, the `silo-node` executable, and the
operator's `silo-ctl nodes` commands.

Rationale: [Silo proposal — Nodes, discovery and approval](../../../Proposals/Silo.md) — a node registers and is given nothing; a person approves; Bonjour is convenience, never mechanism.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: A node mints its identity once and keeps it
`silo-node` SHALL, on a run that finds no `identity.json` in its state directory, mint a
`NodeIdentity` — an id, a lower-cased UUID, and a secret, 32 random bytes rendered as 64
lower-case hex characters by the same `FileRef.mintSecret()` the silo mints secrets with — and
write it atomically; a run that finds one SHALL reuse it. The state directory SHALL default to
`~/.silo-node` and SHALL take `--state-dir`. When approval delivers the token, the token SHALL be
written into the same `identity.json`, so a restart neither registers a new identity nor asks for
the token a second time.

#### Scenario: first run
- **WHEN** `silo-node` starts with an empty state directory
- **THEN** it writes `identity.json` holding a fresh id and secret, and registers with them

#### Scenario: later runs
- **WHEN** `silo-node` starts over a state directory an earlier run used
- **THEN** it registers with the same id and secret it minted on the first run

Pinned by: nothing yet.

### Requirement: A node finds the silo by Bonjour, or is given its URL
`silo-node` SHALL take the silo's URL from `--silo` first and `SILO_URL` second, and only without
both SHALL browse Bonjour for it. Bonjour is convenience, not mechanism: given a URL, a node
never looks for a tool. Browsing that finds several silos SHALL log how many and use the first.
With no URL and no Bonjour tool the run SHALL refuse with `give --silo; no Bonjour tool: dns-sd
on macOS, or avahi-utils on Linux`; with no URL and nothing on the network it SHALL refuse with
`no silo found on this network; give --silo`. A browsed silo SHALL be reached at
`http://<host>:<port>`.

#### Scenario: two silos on the network
- **WHEN** `silo-node` runs with neither `--silo` nor `SILO_URL` and two silos advertise
- **THEN** it logs `2 silos found; using <name>` and registers against the first one browsed

#### Scenario: no URL and no tool
- **WHEN** neither a URL, `dns-sd` nor Avahi's tools are available
- **THEN** the run fails with `give --silo; no Bonjour tool: dns-sd on macOS, or avahi-utils on Linux`

Pinned by: nothing yet.

### Requirement: Registration is recorded pending and given nothing
The silo SHALL serve `POST /v1/nodes` open — a node has nothing yet — taking a `NodeRegistration`
(`id`, `secret`, `name`, `platform`, `capabilities`, and optionally `ffmpegVersion` and `cores`)
and answering 201 with the recorded node. A first registration SHALL be recorded `pending`, with
`registeredAt` and `lastSeenAt` set, and given nothing: no token exists for it. A later
registration of the same id SHALL have to know the secret — a mismatch is 403 — and SHALL then
bring the record's name, platform, capabilities, `ffmpegVersion` and `cores` up to date and touch
`lastSeenAt`. The node record SHALL carry `id`, `name`, `platform`, `state` (one of `pending`,
`approved`, `revoked`), `capabilities` (the encoders the node's `ffmpeg` reports, by name),
`ffmpegVersion`, `cores`, `registeredAt`, `approvedAt` and `lastSeenAt`.

#### Scenario: a node announces itself
- **WHEN** `POST /v1/nodes` receives `{"id": "node-1", "secret": "s3cret", "name": "box", "platform": "Linux", "capabilities": ["flac", "aac"], "ffmpegVersion": "ffmpeg 7", "cores": 4}`
- **THEN** the reply is 201, the recorded node's state is `pending`, and its polls carry no token until it is approved

#### Scenario: the same id registers again
- **WHEN** `node-1` registers again with a secret that is not its own, and then with its own
- **THEN** the first reply is 403 and the second brings the record's name and capabilities up to date

Pinned by: `Tests/SiloTests/ServerTests.swift` (`xNodesRegisterAreApprovedAndTakeWorkWithTheirToken`), `Tests/SiloTests/NodeTests.swift` (`aNodeIsApprovedAndTakesItsTokenOnce`).

### Requirement: Approval is the operator's, and the node's poll takes its token once
The operator's side of nodes SHALL be `GET /v1/nodes` (every node the silo knows, pending ones
included, oldest first), `POST /v1/nodes/{id}/approve` and `POST /v1/nodes/{id}/revoke`, all
three behind the operator's bearer token: 401 without it, 404 for an unknown id. A node SHALL
poll `GET /v1/nodes/{id}` with its secret in the `x-silo-node-secret` header — 404 for an unknown
id, 403 for a secret that is not its. While the node is `pending` the poll SHALL answer the
record and nothing else. Approval SHALL set the state `approved`, record `approvedAt`, and clear
any token that came before; the node's first poll after it SHALL mint a token, 64 lower-case hex
characters, store only its hash, mark it delivered, and carry it in that answer — and every later
poll SHALL carry none, since the node keeps it. Every poll SHALL touch the node's `lastSeenAt`.

#### Scenario: approval through the routes
- **WHEN** `POST /v1/nodes/node-1/approve` arrives with no bearer token, and then with the operator's
- **THEN** the replies are 401 and 200, and `GET /v1/nodes` with the operator's token lists `node-1`

#### Scenario: the token is handed over once
- **WHEN** `node-1` polls `GET /v1/nodes/node-1` with `x-silo-node-secret: s3cret` while pending, then twice after approval
- **THEN** the pending poll carries no token, the first approved poll carries one, and the second carries none again; a poll with `x-silo-node-secret: wrong` is 403 and a poll for `node-9` is 404

Pinned by: `Tests/SiloTests/ServerTests.swift` (`xNodesRegisterAreApprovedAndTakeWorkWithTheirToken`), `Tests/SiloTests/NodeTests.swift` (`aNodeIsApprovedAndTakesItsTokenOnce`).

### Requirement: The node's token gates the working routes, and seeing it is the heartbeat
The node's four job routes — `POST /v1/jobs/claim`, `POST /v1/jobs/{id}/progress`, `POST
/v1/jobs/{id}/complete` and `POST /v1/jobs/{id}/fail` — SHALL sit behind the node gate: a bearer
token that is the operator's passes, and so does one whose SHA-256 matches the stored token hash
of an `approved` node; anything else, including nothing, is 401. A node's token SHALL NOT pass
the operator's gate, and the OpenAPI document SHALL say both with its `node` and `operator`
bearer security schemes. Each accepted node token SHALL touch that node's `lastSeenAt` — seeing
the token is the node's heartbeat. The node named in a request body SHALL be trusted to be the
token's own; on a household network that is enough.

#### Scenario: the two gates
- **WHEN** `node-1` posts to `/v1/jobs/claim` with no token, with `Bearer nope`, and with its issued token
- **THEN** the replies are 401, 401 and 200, and the node token against an operator route — `POST /v1/jobs/nothing/cancel` — is 401

#### Scenario: the heartbeat
- **WHEN** an approved node's token is presented to the silo
- **THEN** the node it belongs to is authenticated and its `lastSeenAt` is set to now

Pinned by: `Tests/SiloTests/ServerTests.swift` (`xNodesRegisterAreApprovedAndTakeWorkWithTheirToken`), `Tests/SiloTests/NodeTests.swift` (`aNodeIsApprovedAndTakesItsTokenOnce`).

### Requirement: Revoking is one state change, effective at once
`POST /v1/nodes/{id}/revoke` SHALL be one state change — the node's state becomes `revoked`, its
token hash and delivered mark are cleared — and nothing else; the revoked token SHALL stop
authenticating with the next request. Approving the node again SHALL mint a fresh token on its
next poll, and the revoked token SHALL stay refused. A `silo-node` that polls and finds itself
revoked SHALL end with `this node has been revoked on the silo`.

#### Scenario: revoke, and approve again
- **WHEN** `node-1` is revoked after taking its token, then approved again and polls
- **THEN** its old token is refused by the node gate at once, the new poll carries a token different from the old, and only the new token authenticates

Pinned by: `Tests/SiloTests/NodeTests.swift` (`aNodeIsApprovedAndTakesItsTokenOnce`), `Tests/SiloTests/ServerTests.swift` (`xNodesRegisterAreApprovedAndTakeWorkWithTheirToken`). The `silo-node` exit line is pinned by nothing yet.

### Requirement: The silo stores hashes of the secret and the token, never either itself
The silo SHALL keep one JSON file per node at `<state>/nodes/<id>.json` holding the record, the
SHA-256 of the node's secret as hex, the SHA-256 of a delivered token as hex, and whether the
token was delivered — and SHALL never store either the secret or the token themselves. Writes
SHALL be atomic. The store SHALL be loaded on boot, so an approved node's token keeps
authenticating across a restart and a delivered token is not handed out a second time.

#### Scenario: nodes survive a restart
- **WHEN** a node was approved and took its token, and a fresh `NodeStore` opens the same folder
- **THEN** the token still authenticates against the node's name, a poll carries no second token, and the JSON on disk contains neither the secret nor the token

Pinned by: `Tests/SiloTests/NodeTests.swift` (`nodesSurviveARestart`).

### Requirement: Bonjour runs as child processes of the platform's own tools
`SiloDiscovery` SHALL do Bonjour through the tools each platform ships — `dns-sd` on macOS, and
`avahi-publish` and `avahi-browse` on Linux — run as child processes, so that nothing Apple-only
is linked and a machine without the tool is told so rather than failed. The service type SHALL be
`_silo._tcp`. Each tool SHALL be located by its environment override (`DNS_SD_PATH`,
`AVAHI_PUBLISH_PATH`, `AVAHI_BROWSE_PATH`) and then on `PATH`; `dns-sd` wins where both exist,
and on a machine with neither `Discovery.isAvailable` SHALL be false and the machine SHALL be
told `no Bonjour tool: dns-sd on macOS, or avahi-utils on Linux`. Advertising SHALL be `dns-sd
-R` or `avahi-publish -s`, with the TXT records sorted by key as `key=value`, and SHALL stay up
for as long as the child process runs, ending when it is terminated. Browsing SHALL collect
`dns-sd -B` for the timeout — three seconds by default — and resolve each added name with `dns-sd
-L`, or on Linux SHALL parse `avahi-browse -rtp`, unescaping Avahi's `\032`; the result SHALL be
one `DiscoveredSilo` per silo — its name, host, port and TXT records — whose URL is
`http://<host>:<port>`.

#### Scenario: dns-sd output is parsed
- **WHEN** `dns-sd -B` prints `Add` lines for `Living Room Silo` and `Study` and an `Rmv` line
- **THEN** browsing hears both names, and the `-L` lookup of the first yields host `nuc.local`, port `8080` and TXT `v=1`

#### Scenario: avahi output is parsed
- **WHEN** `avahi-browse -rtp` prints `=;` lines for `Living\032Room\032Silo` on IPv6 and IPv4, and one for `Study`
- **THEN** two silos are found, each once: `Living Room Silo` at `nuc.local:8080` with its TXT records and `Study` at `study.local:9090`

#### Scenario: the live round trip
- **WHEN** `Discovery.advertise` runs on a machine with a responder, and `Discovery.browse` follows
- **THEN** the advertisement is found by name, with its port and its `v=1` TXT record

Pinned by: `Tests/SiloTests/NodeTests.swift` (`dnssdOutputIsParsed`, `avahiOutputIsParsed`, `anAdvertisedSiloIsFound` — the last skipped where no responder runs, and opted into on Linux with `SILO_TEST_BONJOUR=1`). Tool selection and the unavailable message are pinned by nothing yet.

### Requirement: The silo advertises itself for as long as it runs
The `silo` executable SHALL run an `Advertiser` background service which, when `SILO_ADVERTISE`
is true — the default — advertises the silo's name, `SILO_NAME` defaulting to `Silo on <host
name>`, and its configured port as `_silo._tcp` with TXT `v=1`; it SHALL keep the advertisement
up for the life of the process and drop it at shutdown. `SILO_ADVERTISE=false` SHALL advertise
nothing. On a machine with no Bonjour tool, or where launching one fails, the silo SHALL log
`not advertising` with the reason once and idle, never failing to boot over it.

#### Scenario: the advertisement is browsable
- **WHEN** a silo is advertised under a unique name on a machine with a responder, and a browse follows
- **THEN** it is found by name, with its port and `v=1` in its TXT records

#### Scenario: advertising is off
- **WHEN** the silo boots with `SILO_ADVERTISE=false`
- **THEN** no advertisement process starts and the silo serves as usual

Pinned by: `Tests/SiloTests/NodeTests.swift` (`anAdvertisedSiloIsFound`, skipped where no responder runs). `SILO_ADVERTISE` and `SILO_NAME` are pinned by nothing yet.

### Requirement: The operator steers nodes from silo-ctl
`silo-ctl nodes` SHALL offer `list`, `approve <id>`, `revoke <id>` and `discover`, speaking to
the silo at `--silo` or `SILO_URL` with the token from `--token` or `SILO_TOKEN`. `list` SHALL
print every node the silo knows, pending ones included, one line each — the id, the state, the
name, the platform, the core count, the encoder count and when it was last seen — or `no nodes`.
`approve` and `revoke` SHALL print the decided node's line. `discover` SHALL print the silos
Bonjour can see for `--seconds` (three by default), one line each — the name, the URL and the TXT
records — or `no silos found`, and SHALL refuse on a machine with no Bonjour tool.

#### Scenario: approving from the command line
- **WHEN** `silo-ctl nodes approve <id>` runs against a silo that knows the node
- **THEN** the node's record is approved and its line is printed, and its next poll carries its token

#### Scenario: discovering from the command line
- **WHEN** `silo-ctl nodes discover` runs on a network with one advertising silo
- **THEN** it prints the silo's name, its `http://<host>:<port>` URL and its TXT records

Pinned by: nothing yet.

### Requirement: silo-node is the node's side of it all
`silo-node` SHALL be the executable a machine other than the silo's runs, with the options
`--silo`, `--name` (defaulting to the machine's host name), `--state-dir`, `--serve-port`
(defaulting to 18600), `--advertised-host` (defaulting to the machine's host name) and `--poll`
(the seconds between asking for work, defaulting to 5). On start it SHALL require its `ffmpeg`
and `ffprobe` — a node without them has nothing to offer — and SHALL register its name, its
platform (`macOS`, `Linux` or `other`), the encoders its `ffmpeg` reports sorted, the first line
of `ffmpeg -version`, and the machine's active core count. While unapproved it SHALL poll every
five seconds and log once `waiting for approval: on the silo, run  silo-ctl nodes approve <id>`.
Once it holds its token it SHALL serve what it makes on the serve port under the advertised
host — each output published at `<job>/output` with itself as holder for the silo to fetch at
placement — and SHALL run the worker's loop with the token, the same loop the embedded node
runs, so there is one code path to test.

#### Scenario: approval arrives
- **WHEN** `silo-node` runs unapproved and a person approves its id on the silo
- **THEN** within five seconds a poll takes and saves the token, and the run continues with `ready: <n> encoders, serving outputs on port 18600`

Pinned by: nothing yet.
