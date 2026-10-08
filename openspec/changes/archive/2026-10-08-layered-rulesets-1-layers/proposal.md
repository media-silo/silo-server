<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Layered rulesets, step 1: Layers and provenance

## Why
The rules that decide an entry come in layers, nearest first: each container's rules in force, kept
as versioned files beside its `.smd`, then the ruleset applied — the library's standard when the
application names none. A recipe records the stack it was resolved through, each decision the layer
its rule came from, and placement writes the binding and the stack into the `.smd`. Step 1 of four.
Proposal: [Layered rulesets](../../../Proposals/LayeredRulesets.md).

## What Changes
- A sidecar's `<rules path activeVersion>` and its version files are read, and checked by the walk.
- An application resolves through the stack built from the binding's lineage.
- `audio.index` and `subtitle.index` join the facts.
- A library may name its ruleset, which an application naming none takes.
- A recipe records its stack with each layer's version and digest; a decision names its layer.
- Placement writes `<source binding>` with the binding's segments and `<transform>`; the binding's
  own source reference, `silo-ctl place --source` and the place route's `source` go.
