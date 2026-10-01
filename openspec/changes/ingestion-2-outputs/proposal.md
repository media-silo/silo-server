<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Ingestion, step 2: Outputs in the ruleset

## Why
A ruleset declares the outputs it makes of every entry, each with its profile and container, and is resolved once for each. Step 2 of four. Proposal: [Ingestion: sources, bindings and recipes](../../../Proposals/Ingestion.md).

## What Changes
- `<output>` becomes a list, each with an optional profile.
- Two outputs of one profile, or two unqualified, are refused.
