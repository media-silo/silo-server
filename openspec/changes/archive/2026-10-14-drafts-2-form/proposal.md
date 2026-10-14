<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Drafts, step 2: The form

## Why
The console edits a draft in a form built from the rule language, splicing each change into the text so that everything the change did not touch stays exactly as written. Step 2 of four. Proposal: [Drafts](../../../Proposals/Drafts.md).

## What Changes
- SiloKit reads a ruleset keeping each rule's and output's range in the text, and splices an inserted, replaced, moved or deleted element into it.
- The console's form creates, edits, reorders and deletes rules and outputs through those splices, and does nothing while the text cannot be read.
