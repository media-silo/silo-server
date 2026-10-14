<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Extras, step 2: The fact

## Why
A rule can ask whether the item it decides is an extra, as a fact taken from where its container files it, rather than by listing the types an extra might have, which misses an extra of any other type and every type not listed. Step 2 of three; step 1 names the extra types in SmdKit. Proposal: [Extras](../../../Proposals/Extras.md).

## What Changes
- `extra` is a file-level flag fact, true when the binding's item is held in its container's extras and false when it is held in a sequence, derived with the other facts and recorded in the recipe.
- The resolver's dry run takes an optional `extra`, and `silo-ctl encode` takes `--extra`.
- The example ruleset's `small-extras` tests `extra` instead of listing extra types.
