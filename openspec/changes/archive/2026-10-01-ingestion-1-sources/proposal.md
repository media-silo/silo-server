<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Ingestion, step 1: Sources and input specs

## Why
A producer registers a source by describing it in an input spec, read strictly in the silo's vocabulary; the silo mints its id, finds it again by a natural key, and tracks which nodes hold copies. The silo's own producer describes a plain file from its probe. Step 1 of four. Proposal: [Ingestion: sources, bindings and recipes](../../../Proposals/Ingestion.md).

## What Changes
- An input-specs capability: the vocabulary, its refusals and its versioning, and the plain-file producer.
- A sources capability: registration, natural keys, copies, and open reads without secrets.
- The probe keeps exact frame rates and reads chapters.
