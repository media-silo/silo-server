<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Resolved recipes

## Why
A recipe an application has made, and no job has yet run, was called a draft, and its state was
`draft`. The console's drafts are a ruleset's text being edited, and the drafts proposal keeps them on
the Mac, where nothing can be applied or run; with both named the same, "a job from a draft" reads as
a job from rules that were never stored. A recipe not yet run is resolved — fully decided through a
stored version — and not yet committed, so it is named for that. Decided in review of the drafts
proposal, without a proposal document of its own: there is nothing to migrate, since no silo holds a
recipe yet.

## What Changes
- A recipe's state is `resolved` or `committed`; `draft` is no longer a state.
- The specs, the API document and the code call a recipe not yet run a resolved recipe.
