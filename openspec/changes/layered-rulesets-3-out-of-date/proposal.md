<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Layered rulesets, step 3: Out-of-date presentations

## Why
A placed presentation is out of date when its committed recipe's facts, resolved through the stack
that applies to its binding now, decide an unadjusted stream or its output differently. The silo
works this out when asked, and reports with each one whether its binding's sources have copies, so
the operator knows which can be made again. Step 3 of three. Proposal: [Layered rulesets](../../../Proposals/LayeredRulesets.md).

## What Changes
- The out-of-date comparison, computed on request from recorded facts and the current rules.
- A library's out-of-date report, with each presentation's sources and their copies.
- A branch's impact: the report its promotion would give, changing nothing.
