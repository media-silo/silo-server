<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Onboarding

## Why
How a silo with no configuration becomes a working server: bootstrap mode and the staged, then confirmed, setup pair, the operator's passkey, recovery through the filesystem, and SiloAdmin. Proposal: [Onboarding](../../../../Proposals/Onboarding.md). #13 proposed it; #15, #17, #18, #20 and #21 implemented it.

## What Changes
- Bootstrap mode, the staged and confirmed setup pair, and the operator credential.
- Recovery through a reset file in the state directory.
- SiloAdmin and its engine, finding silos and walking a fresh one through setup.
