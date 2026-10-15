<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Extras, step 3: The console

## Why
The form offers the types SmdKit names when a rule tests an item's kind, so that the operator chooses `deletedScene` rather than remembering how the vocabulary spells it, while still taking any type. Step 3 of three. Proposal: [Extras](../../../Proposals/Extras.md).

## What Changes
- A condition on `kind` offers SmdKit's named types, `episode` and `movie` first and then the extra types, from the menu beside its field.
- A condition on `extra` offers true and false, as any flag does.
