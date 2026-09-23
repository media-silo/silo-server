<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Add jobs, the node's loop, peer-to-peer file serving, and the embedded node

**Retrospective archive — merged 2026-09-23 as pull request #5.** This change predates the
corpus; its documents were reconstructed from the merge afterwards.

## Why

The read path could browse a library and the server could place a file into it, but nothing
turned a rip into a placed file. The proposal's queue — registration, a state machine, a lease
that notices a vanished node — and its file movement principle — a file stays with its holder
until it is placed — needed their implementation, and the first node needed to be the one
inside the silo, so one machine could be the whole pipeline before a second machine exists.

## What Changes

- The job: one JSON file per job under the state directory, the full record — source, probe,
  assignment, merged facts, resolved recipe and its encoder requirements, state, attempts,
  lease, progress, output, result and failure — and the state machine the proposal tables:
  `unassigned` → `pending` → `claimed` → `encoding` → `encoded` → `placing` → `placed`, with
  `failed`, `cancelling` and `cancelled` alongside. A claim is pick-and-lease under one lock,
  preferring a node that already holds the source; a lapsed lease loses the attempt and the
  third loss fails the job; a cancel rides back in the answer to the node's next report.
- Peer-to-peer file serving: a holder publishes each file by `Range`, guarded by a secret
  minted per file and handed only to the claiming node — a request without it is 404, not 401,
  so paths cannot be enumerated — and the fetching side resumes by offset. The media route now
  serves through the same response every node uses, so there is one byte-serving code path.
- The worker: the node's loop — claim, open or fetch the source, encode as the recipe says,
  probe the output, check the layout, report — identical whether it speaks HTTP (`SiloClient`,
  Foundation alone) or asks the job service in process. `SILO_EMBEDDED_NODE=true` runs that
  loop inside the silo; its outputs are moved at placement rather than fetched.
- The operator's `silo-ctl jobs`: `list`, `show`, `cancel`, `retry` and `place`.
- At this merge the job routes take the operator's token throughout; a node's own token
  arrives with the nodes change that follows.

## Impact

- Affected specs: jobs, file-serving, worker
- Affected code: Sources/SiloKit (the job record), Sources/SiloStore (the job store),
  Sources/SiloAPI (the job operations), Sources/SiloApp (the job controller and service),
  Sources/FileServing, Sources/SiloClient, Sources/SiloWorker, Sources/silo (the embedded
  node), Sources/silo-ctl (the jobs commands), Tests/SiloTests (FileServerTests, JobTests,
  ServerTests)
