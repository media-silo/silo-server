<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Tasks

**Retrospective archive — every task was completed in pull request #5 (merged 2026-09-23).**

## 1. The job and its queue

- [x] 1.1 Add the job record and its states to `SiloKit`, and the job store to `SiloStore`
      (one JSON file per job, loaded at start, every transition a locked read-modify-write)
- [x] 1.2 Add the job service: registration, assignment with facts merged and the recipe
      resolved, claim with pick-and-lease, progress as heartbeat, completion checked against
      the recipe's layout, cancel, fail, retry, and reclaiming lapsed leases

## 2. The routes and the operator

- [x] 2.1 Add the job operations to the OpenAPI document and `JobController` behind the
      operator's token, with the two reads open
- [x] 2.2 Add `silo-ctl jobs` (`list`, `show`, `cancel`, `retry`, `place`) over the
      Foundation-only client

## 3. Files move once

- [x] 3.1 Add `FileServing`: publish a file under a secret-guarded path, serve it by `Range`
      with the one response the media route shares, fetch with resume-by-offset
- [x] 3.2 Route the media route through the same response; exercise both over a real socket

## 4. The node

- [x] 4.1 Add `SiloClient`, the silo's API from a client's side over Foundation alone
- [x] 4.2 Add `SiloWorker`: the node's loop — claim, open or fetch, encode, probe, check,
      report, serve the output
- [x] 4.3 Add the embedded node (`SILO_EMBEDDED_NODE`): the same loop inside the silo against
      the job service directly, its outputs placed by move; run the real binary through the
      whole pipeline on one machine
