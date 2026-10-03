<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Ingestion, step 4: Jobs from recipes

## Why
A job is made from a draft recipe and is only the run: a claim hands the node each segment and its span, the node encodes them as one input, and placement builds the presentation from the binding. Registration and assignment go. Step 4 of four. Proposal: [Ingestion: sources, bindings and recipes](../../../Proposals/Ingestion.md).

## What Changes
- Jobs made from recipes; registration, assignment and the unassigned state removed.
- Claims carry segments and spans; the worker joins and cuts them as one concat input.
- Placement from the binding, in the output's profile.
- The merge of a probe and a MakeMKV scan, and roles from MakeMKV's flags, go with the routes that used them; the layout and the resolver speak of the binding's feature map.
