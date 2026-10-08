<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Layered rulesets, step 4: Out-of-date presentations

## Why
When rules change, the silo works out in the background which placed presentations the change can
reach, resolves each again through the rules in force, and records what it finds: current, checked
against these rules, or out of date, with what would change. A report reads the records, with each
out-of-date presentation's sources and their copies. Step 4 of four.
Proposal: [Layered rulesets](../../../Proposals/LayeredRulesets.md).

## What Changes
- A check record per placed presentation: the stack it was checked against, when, and the outcome.
- A background check, started by any change of rules, that can be stopped and resumed.
- A library's out-of-date report, and a branch's impact, resolved on request.
