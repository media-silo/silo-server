<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Layered rulesets, step 2: Branches

## Why
A trial set of rules is a branch of a ruleset's standard, applied to the bindings the operator
chooses, and promoted to be the standard by a fast-forward that never loses what the standard
gained. Step 2 of three. Proposal: [Layered rulesets](../../../Proposals/LayeredRulesets.md).

## What Changes
- Versions record their branch and parent; numbers stay one sequence per ruleset.
- Stores and applications may name a branch.
- Promotion stores a branch's head as the standard's next version, refused over versions it has not
  taken in.
- Routes to list, start, store on and promote branches.
