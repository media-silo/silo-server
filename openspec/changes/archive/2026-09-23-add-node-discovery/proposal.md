<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Add nodes: registration, approval, tokens, Bonjour, and silo-node

**Retrospective archive — merged 2026-09-23 as pull request #6.** This change predates the
corpus; its documents were reconstructed from the merge afterwards.

## Why

Until this change the only node was the one the silo runs inside itself
(`SILO_EMBEDDED_NODE=true`), which made one machine the whole pipeline. This is nodes proper, as
`Proposals/Silo.md` argues under *Nodes, discovery and approval*: a machine that is not the silo
mints its own identity and secret, finds the silo by Bonjour or is handed its URL, registers
what its `ffmpeg` can do, waits pending until a person approves it, and takes its token once —
from then on claiming, reporting and completing with it, until revoking cuts it off in one state
change. *Why not a cluster* holds: every interaction this adds is an operation in the same
OpenAPI document, and Bonjour is convenience, never mechanism — a URL by hand always works.

## What Changes

- **The node record and its store.** `Node` (`pending` / `approved` / `revoked`),
  `NodeRegistration`, `NodeStatus` and `NodeIdentity` arrive in SiloKit, and `NodeStore` keeps
  one JSON file per node under `<state>/nodes` holding the record plus the SHA-256 hashes of the
  node's secret and token — never either itself. swift-crypto arrives for the hashes.
- **The node routes.** `POST /v1/nodes` and `GET /v1/nodes/{id}` are open in the node's secret's
  keeping: a first registration is recorded pending and given nothing, a re-registration has to
  know the secret, and the first poll after approval carries the token — once. `GET /v1/nodes`,
  `POST /v1/nodes/{id}/approve` and `POST /v1/nodes/{id}/revoke` sit behind the operator's token.
- **The token gate.** Claim, progress, complete and fail move to a `JobNodeController` behind a
  new `RequireNode` middleware: an approved node's bearer token or the operator's passes, a
  revoked one stops at once, and a node's token does not pass the operator's gate. Seeing a
  node's token is its heartbeat (`lastSeenAt`).
- **Bonjour as child processes.** New `SiloDiscovery` module: advertise and browse `_silo._tcp`
  through `dns-sd` on macOS or Avahi's tools on Linux, run as processes so nothing Apple-only is
  linked, with the output parsing kept apart so it is tested on captured text. The silo
  advertises itself for as long as it runs (`SILO_NAME`, with `SILO_ADVERTISE=false` to decline),
  and logs once rather than failing when no tool exists.
- **The `silo-node` executable.** Mints and keeps `identity.json` in its state directory, takes
  the silo from `--silo`, `SILO_URL` or Bonjour, registers its name, platform, encoders, ffmpeg
  version and cores, polls until approved, then serves its outputs on `--serve-port` and runs
  the same worker loop the embedded node runs.
- **The operator's command line.** `silo-ctl nodes` gains `list`, `approve <id>`, `revoke <id>`
  and `discover`, speaking to the silo at `--silo`/`SILO_URL` with `--token`/`SILO_TOKEN`.

## Impact

- Affected specs: `node-discovery` (new); `jobs` (modified — the four working routes move from
  the operator's token to the node gate)
- Affected code: `Package.swift` and `Package.resolved` (swift-crypto; the SiloDiscovery module
  and the silo-node target); `Sources/SiloKit/Node.swift`, `Sources/SiloStore/NodeStore.swift`,
  `Sources/SiloDiscovery/Discovery.swift`, `Sources/SiloApp/NodeService.swift`,
  `Sources/SiloApp/NodeController.swift`, `Sources/silo-node/SiloNode.swift`,
  `Sources/silo/Advertiser.swift`, `Sources/silo-ctl/Nodes.swift` (new);
  `Sources/SiloApp/{Auth,JobController,SiloConfig}.swift`, `Sources/SiloAPI/openapi.yaml`,
  `Sources/SiloClient/SiloClient.swift`, `Sources/Encoder/{FFmpeg,FFprobe,ProcessRunner}.swift`,
  `Sources/silo/ApplicationWiring.swift`, `Sources/silo-ctl/SiloCtl.swift` (modified);
  `Tests/SiloTests/NodeTests.swift` (new), `Tests/SiloTests/ServerTests.swift` (modified);
  `.github/workflows/build.yml` (CI installs avahi-utils); `README.md`.
