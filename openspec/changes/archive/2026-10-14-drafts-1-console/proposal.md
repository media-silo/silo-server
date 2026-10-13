<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Drafts, step 1: Drafts on the Mac

## Why
A draft of a ruleset is the console's working copy: kept on the Mac as it is edited, listed under the branch it was based on, and committed to the silo by the store 0008 made, which is refused and keeps the draft when the head has moved. The silo holds versions and never work in progress. The console also reads a draft itself, with the reader the silo runs, and shows it parsed or as its text. Step 1 of four. Proposal: [Drafts](../../../Proposals/Drafts.md).

## What Changes
- The console keeps drafts on disk per silo, saved a moment after the operator stops editing, and lists each under its base's branch, marked behind when the branch has moved.
- A draft is shown parsed, read-only, or as its text, the parsed view giving the reader's refusal, with line and column, when the text cannot be read.
- Forgetting a silo deletes its drafts.
