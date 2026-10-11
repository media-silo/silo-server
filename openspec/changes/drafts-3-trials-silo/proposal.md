<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Drafts, step 3: Trials on the silo

## Why
A change is tried before it is promoted by committing it to a branch, applying the branch to chosen bindings, and making trial jobs of the recipes: encoded like any job, kept in a trial area of the silo's state, served from there, and never placed. A trial's recipe names its version, as every recipe does. Step 3 of four. Proposal: [Drafts](../../../Proposals/Drafts.md).

## What Changes
- `POST /v1/jobs` takes `trial`; a trial job is claimed and encoded as any job is.
- An encoded trial job's output is fetched into `<state>/trials` and the job becomes `tried`; placement refuses a trial.
- Trials are listed, served by range and deleted.
