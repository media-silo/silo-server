<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Layered rulesets, step 1: Layers

## Why
The rules that decide an entry come in layers, nearest first: the `<rules>` a container's sidecar
carries, then its ancestors', then the ruleset applied — the library's standard when the application
names none. A recipe records the container layers it was resolved against, and each decision the
layer its rule came from. Step 1 of three. Proposal: [Layered rulesets](../../../Proposals/LayeredRulesets.md).

## What Changes
- A sidecar's `<rules>` is read and checked by the walk; a refused one is an error finding.
- An application resolves through the stack built from the binding's lineage.
- A library may name its ruleset, which an application naming none takes.
- A recipe records its container layers, kept by digest; a decision names its layer.
