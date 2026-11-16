<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A binding and an application are recognised by what they say

## Why
A binding sent again because its answer was lost is a second binding of one entry, and a ruleset
applied again makes a second set of resolved recipes beside the first. Each is recognised instead by
what it says, and answered with the record already there. Proposal:
[0022-repeats](../../../Proposals/Repeats.md).

## What Changes
- A binding that says what a binding the silo holds says, but for its lineage's documents, is answered
  200 with that binding, and nothing is stored.
- An application answers, for each output, a recipe the binding already holds whose facts and recipe
  are the ones it resolves, in place of a new one; one that makes none is answered 200, and stores
  nothing.

## Impact
- Modified: a binding says what one entry is made from; applying a ruleset to a binding makes a
  resolved recipe for each output.
