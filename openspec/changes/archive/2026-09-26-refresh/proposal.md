<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Refresh

## Why
SiloAdmin keeps itself current: no manual refresh, a damped fall to unreachable, and a gone-quiet silo or a refused passkey announced in words. Proposal: [Refresh](../../../../Proposals/Refresh.md). #23 proposed it; #24, #25 and #26 implemented it.

## What Changes
- The console refreshes on its own; sweeps coalesce.
- One missed sweep holds a silo's class; the second calls it unreachable.
- A gone-quiet silo is dimmed and bannered, and a refused passkey is named.
