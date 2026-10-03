<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Ingestion, step 3: Bindings and recipes

## Why
A binding says what one entry is made from — segments of sources joined in order — and resolves to a draft recipe for each output, which a producer may adjust before it is committed. Step 3 of four. Proposal: [Ingestion: sources, bindings and recipes](../../../Proposals/Ingestion.md).

## What Changes
- A bindings capability.
- Facts derived from a binding, its sources and an output, with language, script and region from BCP 47 tags.
- Draft recipes per output, adjustments, committing, and resolving again.
- The dry run and `silo-ctl encode` take input specs.
