<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Tasks

**Retrospective archive — every task was completed in pull request #6 (merged 2026-09-23).**

## 1. The node record and its store

- [x] 1.1 Add `Node`, `NodeRegistration`, `NodeStatus` and `NodeIdentity` to SiloKit (`Sources/SiloKit/Node.swift`), with `NodeState` as `pending` / `approved` / `revoked`
- [x] 1.2 Add `NodeStore` (`Sources/SiloStore/NodeStore.swift`): one JSON file per node under `<state>/nodes`, holding SHA-256 hashes of the secret and token, never either itself; add swift-crypto to `Package.swift`
- [x] 1.3 Provide the store from `Sources/silo/ApplicationWiring.swift` at the state directory's `nodes`

## 2. The node routes and the token gate

- [x] 2.1 Add `NodeService` (`Sources/SiloApp/NodeService.swift`): register pending, re-register only for the secret's holder, poll for status, approve, revoke, and authenticate by token hash — the token handed over once
- [x] 2.2 Add `NodeController` and `NodeOperatorController` (`Sources/SiloApp/NodeController.swift`): the node's two routes open in its secret's keeping, the operator's three behind the operator token
- [x] 2.3 Move claim, progress, complete and fail into a `JobNodeController` behind a new `RequireNode` middleware (`Sources/SiloApp/JobController.swift`, `Sources/SiloApp/Auth.swift`), which an approved node's token or the operator's passes
- [x] 2.4 Describe the Nodes tag, the node schemas, the `x-silo-node-secret` header and the node security scheme in `Sources/SiloAPI/openapi.yaml`
- [x] 2.5 Add the node calls and per-request headers to `Sources/SiloClient/SiloClient.swift`

## 3. Bonjour through the platform's tools

- [x] 3.1 Add SiloDiscovery (`Sources/SiloDiscovery/Discovery.swift`): advertise and browse `_silo._tcp` via `dns-sd` or Avahi's tools as child processes, with the parsing kept apart so it is tested on captured output
- [x] 3.2 Open `ProcessRunner`, `OutputCollector` and `LineSplitter` in Encoder to package visibility for it (`Sources/Encoder/ProcessRunner.swift`, `Sources/Encoder/FFprobe.swift`)
- [x] 3.3 Add `FFmpeg.version()` (`Sources/Encoder/FFmpeg.swift`) so a node can say which build it runs
- [x] 3.4 Add the `Advertiser` background service (`Sources/silo/Advertiser.swift`) and the `SILO_NAME` / `SILO_ADVERTISE` configuration (`Sources/SiloApp/SiloConfig.swift`)

## 4. The silo-node executable

- [x] 4.1 Add `Sources/silo-node/SiloNode.swift`: mint and keep `identity.json`, take the silo from `--silo`, `SILO_URL` or Bonjour, register, and poll until approved
- [x] 4.2 Serve the outputs on `--serve-port` under the advertised host and run the worker's loop with the token

## 5. The operator's command line

- [x] 5.1 Add `silo-ctl nodes` (`Sources/silo-ctl/Nodes.swift`): `list`, `approve`, `revoke` and `discover`, on the shared `--silo` / `SILO_URL` and `--token` / `SILO_TOKEN` connection
- [x] 5.2 Register the subcommand in `Sources/silo-ctl/SiloCtl.swift`

## 6. Tests, CI and documentation

- [x] 6.1 Add `NodeServiceTests` (`Tests/SiloTests/NodeTests.swift`): the approval lifecycle on the service, and nodes surviving a restart with only hashes on disk
- [x] 6.2 Add `DiscoveryTests`: the dns-sd and Avahi parsers on captured output, and a live advertise-and-browse test that skips without a responder (opted into with `SILO_TEST_BONJOUR=1`)
- [x] 6.3 Add the node-routes round trip to `Tests/SiloTests/ServerTests.swift`
- [x] 6.4 Install avahi-utils in CI (`.github/workflows/build.yml`)
- [x] 6.5 Document the node, its approval and `SILO_ADVERTISE` in `README.md`
