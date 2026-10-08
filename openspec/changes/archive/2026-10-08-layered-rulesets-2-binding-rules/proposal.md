<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Layered rulesets, step 2: A binding's own rules

## Why
A person's decision about one entry is a rule in the binding's own rules, the layer nearest any file
made from it, versioned like a container's and named on the item the binding binds. It replaces
adjusting a draft, so the decision is kept and made again the same way whenever the entry's file is.
Step 2 of four. Proposal: [Layered rulesets](../../../Proposals/LayeredRulesets.md).

## What Changes
- A binding's rules are the nearest layer, ahead of every container's.
- `PUT` and `GET /v1/bindings/{id}/rules`; versions kept in the silo until the binding's first
  placement, which writes them into the library, and in the library after.
- An item's `<rules binding path activeVersion>` is read and checked by the walk.
- Draft adjustments are removed.
