<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Rulesets in the console, step 1: What the silo tells the console

## Why
The console reads, checks and tries rulesets through the silo and never parses one itself: the silo
reports every version with its branch, parent and the presentations it made; reads a document for it;
checks a draft and reports a draft's impact without storing anything; and refuses a store that would
land on a head the editor never saw. Step 1 of three. Proposal: [Rulesets in the console](../../../Proposals/Rulesets.md).

## What Changes
- `versions` and `standard` in a ruleset's summary; `reading` in its document.
- `POST /v1/rulesets/{name}/check` and `POST /v1/rulesets/{name}/impact`, storing nothing.
- `basedOn` on `PUT /v1/rulesets/{name}`: 409 naming the head when it is no longer the base.
